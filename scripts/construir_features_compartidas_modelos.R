library(arrow)
library(data.table)
library(dplyr)

path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
path_segmento <- "data/processed/cluster_territorial/cluster_segmento_censal"
path_feriados <- "data/reference/feriados/feriados.R"
out_base <- "data/processed/features_compartidas"

ventanas <- c(7L, 30L)
rezago_com_dias <- 2L
fuerza_prior_barrio <- 30
fuerza_prior_global <- 200
tope_exceso <- 3

dir.create(out_base, recursive = TRUE, showWarnings = FALSE)

rolling_previo <- function(x, n, rezago = 2L) {
  acumulado <- cumsum(x)
  data.table::shift(acumulado, rezago, fill = 0) -
    data.table::shift(acumulado, n + rezago, fill = 0)
}

cargar_feriados <- function(path) {
  if (!file.exists(path)) stop("No existe el calendario de feriados: ", path)
  env <- new.env(parent = baseenv())
  sys.source(path, envir = env)
  if (!exists("diasDesc", envir = env, inherits = FALSE)) {
    stop("El calendario no define diasDesc")
  }
  sort(unique(as.IDate(get("diasDesc", envir = env, inherits = FALSE))))
}

features <- as.data.table(as.data.frame(
  arrow::open_dataset(path_features, format = "parquet") |>
    dplyr::select(
      version_cluster, cluster_id, dia, tuvo_reclamo,
      mean_tiempo_desde_ultimo_levante_pred,
      mean_levante_periodo,
      mean_ratio_tiempo_periodo_pred
    ) |>
    dplyr::collect()
))
features[, dia := as.IDate(dia)]
features[, y := as.integer(tuvo_reclamo)]

versiones <- unique(features$version_cluster)
if (length(versiones) != 1L) stop("Se esperaba una sola version_cluster")
version_cluster_obj <- versiones[[1L]]

admin <- as.data.table(as.data.frame(
  arrow::open_dataset(path_admin, format = "parquet") |>
    dplyr::filter(version_cluster == version_cluster_obj) |>
    dplyr::select(cluster_id, nombre_barrio_ine) |>
    dplyr::collect()
))
setnames(admin, "nombre_barrio_ine", "barrio")

segmentos <- as.data.table(as.data.frame(
  arrow::open_dataset(path_segmento, format = "parquet") |>
    dplyr::filter(version_cluster == version_cluster_obj) |>
    dplyr::select(
      cluster_id, codseg_centroide,
      porc_nbi_segmento, densidad_pob_km2
    ) |>
    dplyr::collect()
))
segmentos[, segmento := as.character(codseg_centroide)]
segmentos[, codseg_centroide := NULL]

geo <- segmentos[admin, on = "cluster_id"]
if (anyDuplicated(geo$cluster_id)) stop("Cluster duplicado en geografia")
if (geo[is.na(barrio) | is.na(segmento), .N] > 0L) {
  stop("Hay clusters sin barrio o segmento")
}

datos <- geo[features, on = "cluster_id"]
setorder(datos, cluster_id, dia)

for (L in ventanas) {
  datos[, paste0("eventos_c_", L) := rolling_previo(y, L, rezago_com_dias),
    by = cluster_id]
  datos[, paste0("expo_c_", L) := rolling_previo(rep(1L, .N), L, rezago_com_dias),
    by = cluster_id]
}

barrio_dia <- datos[, .(eventos = sum(y), exposicion = .N), by = .(barrio, dia)]
setorder(barrio_dia, barrio, dia)
global_dia <- barrio_dia[, .(
  eventos = sum(eventos),
  exposicion = sum(exposicion)
), by = dia]
setorder(global_dia, dia)

for (L in ventanas) {
  global_dia[, paste0("eventos_g_", L) := rolling_previo(eventos, L, rezago_com_dias)]
  global_dia[, paste0("expo_g_", L) := rolling_previo(exposicion, L, rezago_com_dias)]
  global_dia[, paste0("q_g_", L) :=
    get(paste0("eventos_g_", L)) / get(paste0("expo_g_", L))]

  barrio_dia[, paste0("eventos_b_", L) := rolling_previo(eventos, L, rezago_com_dias),
    by = barrio]
  barrio_dia[, paste0("expo_b_", L) := rolling_previo(exposicion, L, rezago_com_dias),
    by = barrio]
  col_qg <- paste0("q_g_", L)
  barrio_dia[global_dia, on = "dia", (col_qg) := get(paste0("i.", col_qg))]
  barrio_dia[, paste0("q_b_", L) := (
    get(paste0("eventos_b_", L)) + fuerza_prior_global * get(col_qg)
  ) / (
    get(paste0("expo_b_", L)) + fuerza_prior_global
  )]
}

for (L in ventanas) {
  col_qb <- paste0("q_b_", L)
  datos[barrio_dia, on = c("barrio", "dia"),
    (col_qb) := get(paste0("i.", col_qb))]
  datos[, paste0("q_", L) := (
    get(paste0("eventos_c_", L)) + fuerza_prior_barrio * get(col_qb)
  ) / (
    get(paste0("expo_c_", L)) + fuerza_prior_barrio
  )]
}

datos[, h_exceso := pmin(
  pmax(mean_ratio_tiempo_periodo_pred - 1, 0),
  tope_exceso
)]
for (L in ventanas) {
  datos[, paste0("w_", L) := get(paste0("q_", L)) * h_exceso]
}

q_cols <- paste0("q_", ventanas)
datos[, propensiones_validas := Reduce(`&`, lapply(.SD, is.finite)), .SDcols = q_cols]
datos[, operativas_validas :=
  is.finite(mean_tiempo_desde_ultimo_levante_pred) &
  is.finite(mean_levante_periodo) &
  is.finite(mean_ratio_tiempo_periodo_pred) &
  is.finite(h_exceso)]

base_segmento_dia <- datos[propensiones_validas & operativas_validas, {
  k_top20_h <- max(1L, ceiling(.N * 0.20))
  list(
    n_clusters = .N,
    observado = sum(y),
    media_tiempo_levante = mean(mean_tiempo_desde_ultimo_levante_pred),
    media_periodo = mean(mean_levante_periodo),
    media_ratio = mean(mean_ratio_tiempo_periodo_pred),
    media_h = mean(h_exceso),
    media_top20_h = mean(head(sort(h_exceso, decreasing = TRUE), k_top20_h)),
    prop_exceso_positivo = mean(h_exceso > 0),
    prop_exceso_mayor_1 = mean(h_exceso > 1),
    media_q_7 = mean(q_7),
    rms_q_7 = sqrt(mean(q_7^2)),
    media_w_7 = mean(w_7),
    rms_w_7 = sqrt(mean(w_7^2)),
    media_q_30 = mean(q_30),
    rms_q_30 = sqrt(mean(q_30^2)),
    media_w_30 = mean(w_30),
    rms_w_30 = sqrt(mean(w_30^2)),
    porc_nbi_segmento = data.table::first(porc_nbi_segmento),
    densidad_pob_km2 = data.table::first(densidad_pob_km2)
  )
}, by = .(version_cluster, dia, barrio, segmento)]

base_segmento_dia[, `:=`(
  prop_reclamo = observado / n_clusters,
  delta_q_7_30 = media_q_7 - media_q_30,
  log_densidad_pob = log1p(densidad_pob_km2)
)]

feriados <- cargar_feriados(path_feriados)
calendario <- data.table(dia = seq(min(features$dia), max(features$dia), by = "day"))
calendario[, `:=`(
  dia_semana = as.integer(format(dia, "%u")),
  mes = as.integer(format(dia, "%m")),
  dia_juliano = as.integer(format(dia, "%j")),
  fin_de_semana = as.integer(format(dia, "%u")) %in% c(6L, 7L),
  es_feriado = dia %in% feriados,
  vispera_feriado = (dia + 1L) %in% feriados,
  post_feriado = (dia - 1L) %in% feriados
)]
calendario[, dia_habil := !fin_de_semana & !es_feriado]
calendario[, angulo_anual := 2 * pi * (dia_juliano - 1) / 365.25]
calendario[, `:=`(
  sin_anual = sin(angulo_anual),
  cos_anual = cos(angulo_anual),
  anio = as.integer(format(dia, "%Y")),
  anio_mes = as.integer(format(dia, "%Y%m"))
)]

base_segmento_dia[calendario, on = "dia", `:=`(
  dia_semana = i.dia_semana,
  mes = i.mes,
  dia_juliano = i.dia_juliano,
  fin_de_semana = i.fin_de_semana,
  es_feriado = i.es_feriado,
  vispera_feriado = i.vispera_feriado,
  post_feriado = i.post_feriado,
  dia_habil = i.dia_habil,
  sin_anual = i.sin_anual,
  cos_anual = i.cos_anual,
  anio = i.anio,
  anio_mes = i.anio_mes
)]

if (anyDuplicated(base_segmento_dia, by = c("version_cluster", "dia", "barrio", "segmento"))) {
  stop("Hay claves duplicadas en la base segmento/dia")
}
if (base_segmento_dia[!is.finite(porc_nbi_segmento) | !is.finite(densidad_pob_km2), .N]) {
  stop("Hay filas sin NBI o densidad")
}

arrow::write_dataset(
  base_segmento_dia,
  path = file.path(out_base, "segmento_dia"),
  format = "parquet",
  partitioning = c("version_cluster", "anio", "anio_mes"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)
arrow::write_parquet(
  calendario,
  sink = file.path(out_base, "calendario_dia.parquet"),
  compression = "zstd"
)

metadata <- data.table(
  version_cluster = version_cluster_obj,
  fecha_min = min(base_segmento_dia$dia),
  fecha_max = max(base_segmento_dia$dia),
  filas_segmento_dia = nrow(base_segmento_dia),
  filas_cluster_dia_fuente = nrow(features),
  filas_cluster_dia_modelables = datos[propensiones_validas & operativas_validas, .N],
  cobertura_cluster_dia_pct = 100 *
    datos[propensiones_validas & operativas_validas, .N] / nrow(features),
  observados_fuente = sum(features$y),
  observados_modelables = datos[propensiones_validas & operativas_validas, sum(y)],
  clusters_fuente = uniqueN(features$cluster_id),
  segmentos = uniqueN(base_segmento_dia$segmento),
  barrios = uniqueN(base_segmento_dia$barrio),
  ventanas = paste(ventanas, collapse = ","),
  rezago_com_dias = rezago_com_dias,
  fuerza_prior_barrio = fuerza_prior_barrio,
  fuerza_prior_global = fuerza_prior_global,
  tope_exceso = tope_exceso,
  incluye_splits = FALSE,
  incluye_clima = FALSE
)
fwrite(metadata, file.path(out_base, "metadata_features_compartidas.csv"))

print(metadata)
print(base_segmento_dia[, .(
  filas = .N,
  observado = sum(observado),
  n_clusters = sum(n_clusters)
), by = anio_mes][order(anio_mes)])
