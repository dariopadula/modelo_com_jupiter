library(arrow)
library(data.table)
library(mgcv)

set.seed(20260915)

path_pred <- paste0(
  "app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia/",
  "modelo_id=com_reclamo"
)
path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
path_segmento <- "data/processed/cluster_territorial/cluster_segmento_censal"
path_territorio <- "data/processed/cluster_territorial/cluster_segmento_censal"
path_feriados <- file.path("data", "reference", "feriados", "feriados.R")
path_viento <- file.path(
  "data", "raw", "inumet", "datos_abiertos",
  "inumet_intensidad_de_viento.csv"
)
path_out <- file.path(
  "outputs", "modelo_inferencial_segmento_com",
  "exploracion_q30_estacionalidad_clima_d1"
)
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

estacion_fuente <- "Aeropuerto Melilla G3"
ventanas <- c(7L, 30L)
rezago <- 2L
fuerza_prior_barrio <- 30
fuerza_prior_global <- 200
tope_exceso <- 3

rolling_previo <- function(x, n, rezago = 2L) {
  acumulado <- cumsum(x)
  shift(acumulado, rezago, fill = 0) -
    shift(acumulado, n + rezago, fill = 0)
}

pred <- as.data.table(as.data.frame(
  open_dataset(path_pred) |>
    dplyr::select(
      cluster_id, dia_objetivo, version_cluster, tuvo_reclamo_observado
    ) |>
    dplyr::collect()
))
pred[, dia_objetivo := as.IDate(dia_objetivo)]
pred <- pred[!is.na(tuvo_reclamo_observado)]
pred[, y := as.integer(tuvo_reclamo_observado == 1L)]

version_cluster_obj <- unique(pred$version_cluster)
if (length(version_cluster_obj) != 1L) stop("Se esperaba una version_cluster")

features <- as.data.table(as.data.frame(
  open_dataset(path_features) |>
    dplyr::filter(version_cluster %in% version_cluster_obj) |>
    dplyr::select(
      cluster_id, dia, version_cluster,
      mean_tiempo_desde_ultimo_levante_pred,
      mean_levante_periodo,
      mean_ratio_tiempo_periodo_pred
    ) |>
    dplyr::collect()
))
setnames(features, "dia", "dia_objetivo")
features[, dia_objetivo := as.IDate(dia_objetivo)]

admin <- as.data.table(as.data.frame(open_dataset(path_admin)))[
  version_cluster == version_cluster_obj,
  .(cluster_id, barrio = nombre_barrio_ine)
]
segmento <- as.data.table(as.data.frame(open_dataset(path_segmento)))[
  version_cluster == version_cluster_obj,
  .(cluster_id, segmento = as.character(codseg_centroide))
]
geo <- segmento[admin, on = "cluster_id"]
if (anyDuplicated(geo$cluster_id)) stop("Cluster duplicado en geografia")

datos <- features[pred, on = c("cluster_id", "dia_objetivo", "version_cluster")]
datos <- geo[datos, on = "cluster_id"]
datos[is.na(barrio) | !nzchar(barrio), barrio := "SIN_BARRIO"]
datos[is.na(segmento) | !nzchar(segmento), segmento := "SIN_SEGMENTO"]
setorder(datos, cluster_id, dia_objetivo)

for (L in ventanas) {
  datos[, paste0("eventos_c_", L) := rolling_previo(y, L, rezago),
    by = cluster_id]
  datos[, paste0("expo_c_", L) := rolling_previo(rep(1, .N), L, rezago),
    by = cluster_id]
}

barrio_dia <- datos[, .(eventos = sum(y), exposicion = .N),
  by = .(barrio, dia_objetivo)]
setorder(barrio_dia, barrio, dia_objetivo)
global_dia <- barrio_dia[, .(
  eventos = sum(eventos), exposicion = sum(exposicion)
), by = dia_objetivo]
setorder(global_dia, dia_objetivo)

for (L in ventanas) {
  global_dia[, paste0("eventos_g_", L) := rolling_previo(eventos, L, rezago)]
  global_dia[, paste0("expo_g_", L) := rolling_previo(exposicion, L, rezago)]
  global_dia[, paste0("q_g_", L) :=
    get(paste0("eventos_g_", L)) / get(paste0("expo_g_", L))]

  barrio_dia[, paste0("eventos_b_", L) := rolling_previo(eventos, L, rezago),
    by = barrio]
  barrio_dia[, paste0("expo_b_", L) := rolling_previo(exposicion, L, rezago),
    by = barrio]
  col_qg <- paste0("q_g_", L)
  barrio_dia[global_dia, on = "dia_objetivo",
    (col_qg) := get(paste0("i.", col_qg))]
  barrio_dia[, paste0("q_b_", L) := (
    get(paste0("eventos_b_", L)) +
      fuerza_prior_global * get(paste0("q_g_", L))
  ) / (
    get(paste0("expo_b_", L)) + fuerza_prior_global
  )]
}

for (col in paste0("q_b_", ventanas)) {
  datos[barrio_dia, on = c("barrio", "dia_objetivo"),
    (col) := get(paste0("i.", col))]
}
for (L in ventanas) {
  datos[, paste0("q_", L) := (
    get(paste0("eventos_c_", L)) +
      fuerza_prior_barrio * get(paste0("q_b_", L))
  ) / (
    get(paste0("expo_c_", L)) + fuerza_prior_barrio
  )]
}

datos[, h_exceso := pmin(
  pmax(mean_ratio_tiempo_periodo_pred - 1, 0),
  tope_exceso
)]
q_validas <- datos[, Reduce(`&`, lapply(.SD, is.finite)),
  .SDcols = paste0("q_", ventanas)]
datos <- datos[
  dia_objetivo >= as.IDate("2025-02-01") &
    dia_objetivo <= as.IDate("2026-05-24") &
    is.finite(h_exceso) & q_validas
]

base <- datos[, .(
  n_clusters = .N,
  observado = sum(y),
  media_h = mean(h_exceso),
  media_q_7 = mean(q_7),
  media_q_30 = mean(q_30)
), by = .(dia_objetivo, barrio, segmento)]
base[, delta_q_7_30 := media_q_7 - media_q_30]

territorio <- as.data.table(as.data.frame(
  open_dataset(path_territorio) |>
    dplyr::select(codseg_centroide, porc_nbi_segmento, densidad_pob_km2) |>
    dplyr::collect()
))
territorio[, segmento := as.character(codseg_centroide)]
territorio <- territorio[, .(
  n_nbi = uniqueN(porc_nbi_segmento),
  n_densidad = uniqueN(densidad_pob_km2),
  porc_nbi_segmento = first(porc_nbi_segmento),
  densidad_pob_km2 = first(densidad_pob_km2)
), by = segmento]
if (territorio[n_nbi > 1L | n_densidad > 1L, .N]) {
  stop("Un segmento tiene mas de un valor territorial")
}
territorio[, c("n_nbi", "n_densidad") := NULL]
base[territorio, on = "segmento", `:=`(
  porc_nbi_segmento = i.porc_nbi_segmento,
  densidad_pob_km2 = i.densidad_pob_km2
)]
if (base[!is.finite(porc_nbi_segmento) | !is.finite(densidad_pob_km2), .N]) {
  stop("Hay filas sin variables territoriales")
}

env_feriados <- new.env(parent = baseenv())
sys.source(path_feriados, envir = env_feriados)
feriados <- as.IDate(env_feriados$diasDesc)

base[, split_modelo := fcase(
  dia_objetivo >= as.IDate("2025-02-01") &
    dia_objetivo <= as.IDate("2026-01-31"), "entrenamiento",
  dia_objetivo >= as.IDate("2026-02-01") &
    dia_objetivo <= as.IDate("2026-03-31"), "validacion",
  dia_objetivo >= as.IDate("2026-04-01") &
    dia_objetivo <= as.IDate("2026-05-24"), "test",
  default = "fuera_split"
)]
base <- base[split_modelo != "fuera_split"]
base[, `:=`(
  prop_reclamo = observado / n_clusters,
  dia_semana = factor(weekdays(dia_objetivo)),
  es_feriado = factor(as.integer(dia_objetivo %in% feriados)),
  mes = factor(format(dia_objetivo, "%m"), levels = sprintf("%02d", 1:12)),
  angulo_anual = 2 * pi * (as.integer(format(dia_objetivo, "%j")) - 1) / 365.25,
  barrio = factor(barrio),
  segmento = factor(segmento),
  log_densidad_pob = log1p(densidad_pob_km2)
)]
base[, `:=`(
  sin_anual = sin(angulo_anual),
  cos_anual = cos(angulo_anual)
)]

# Maximo de las 12 observaciones biorarias de D-1. Los dias incompletos se
# imputan con la mediana de entrenamiento y conservan un indicador explicito.
viento <- fread(
  path_viento,
  sep = ";",
  na.strings = c("", "NA"),
  encoding = "UTF-8"
)
viento <- viento[
  estacion_id == estacion_fuente & !is.na(fecha) & !is.na(int_viento)
]
viento[, fecha_hora := as.POSIXct(
  fecha,
  format = "%Y-%m-%d %H:%M",
  tz = "America/Montevideo"
)]
viento[, dia_observado := as.IDate(fecha_hora, tz = "America/Montevideo")]
viento_diario <- viento[, .(
  viento_max_d1_kmh = max(as.numeric(int_viento)),
  n_obs_viento_d1 = .N
), by = dia_observado]
viento_diario[n_obs_viento_d1 != 12L, viento_max_d1_kmh := NA_real_]
viento_diario[, dia_objetivo := dia_observado + 1L]
base[viento_diario, on = "dia_objetivo", `:=`(
  viento_max_d1_kmh = i.viento_max_d1_kmh,
  n_obs_viento_d1 = i.n_obs_viento_d1
)]
base[, viento_faltante_d1 := factor(as.integer(!is.finite(viento_max_d1_kmh)))]
mediana_viento_train <- base[
  split_modelo == "entrenamiento" & is.finite(viento_max_d1_kmh),
  median(viento_max_d1_kmh)
]
base[!is.finite(viento_max_d1_kmh), viento_max_d1_kmh := mediana_viento_train]

variables_continuas <- c(
  "log_densidad_pob", "porc_nbi_segmento", "media_h",
  "media_q_30", "delta_q_7_30"
)
preparacion <- rbindlist(lapply(variables_continuas, function(variable) {
  x <- base[split_modelo == "entrenamiento", get(variable)]
  mediana <- median(x[is.finite(x)], na.rm = TRUE)
  x[!is.finite(x)] <- mediana
  data.table(
    variable = variable,
    mediana_train = mediana,
    media_train = mean(x),
    sd_train = sd(x)
  )
}))
for (variable in variables_continuas) {
  indice_variable <- match(variable, preparacion[["variable"]])
  p <- preparacion[indice_variable]
  x <- base[[variable]]
  x[!is.finite(x)] <- p$mediana_train
  base[, paste0("z_", variable) := (x - p$media_train) / p$sd_train]
}
fwrite(preparacion, file.path(path_out, "preparacion_variables.csv"))

train <- droplevels(base[split_modelo == "entrenamiento"])
if (length(setdiff(levels(base$mes), unique(as.character(train$mes))))) {
  stop("Hay meses no observados en entrenamiento")
}

formula_referencia <- prop_reclamo ~
  dia_semana + es_feriado +
  z_log_densidad_pob + z_porc_nbi_segmento +
  z_media_h + z_media_q_30 + z_delta_q_7_30 +
  z_media_h:z_delta_q_7_30 +
  z_media_h:dia_semana +
  s(barrio, bs = "re") + s(segmento, bs = "re")

formulas <- list(
  q30_referencia = formula_referencia,
  q30_ciclo_armonico = update(
    formula_referencia,
    . ~ . + sin_anual + cos_anual
  ),
  q30_mes = update(
    formula_referencia,
    . ~ . + mes
  ),
  q30_ciclo_viento_max = update(
    formula_referencia,
    . ~ . + sin_anual + cos_anual +
      viento_faltante_d1 + s(viento_max_d1_kmh, bs = "cr", k = 4)
  ),
  q30_mes_viento_max = update(
    formula_referencia,
    . ~ . + mes +
      viento_faltante_d1 + s(viento_max_d1_kmh, bs = "cr", k = 4)
  )
)

predecir <- function(fit, datos, train) {
  segmentos_train <- levels(train$segmento)
  barrios_train <- levels(train$barrio)
  es_nuevo <- !as.character(datos$segmento) %in% segmentos_train
  pred <- rep(NA_real_, nrow(datos))
  if (any(!es_nuevo)) {
    nd <- as.data.frame(datos[!es_nuevo])
    nd$segmento <- factor(nd$segmento, levels = segmentos_train)
    nd$barrio <- factor(nd$barrio, levels = barrios_train)
    pred[!es_nuevo] <- predict(fit, newdata = nd, type = "response")
  }
  if (any(es_nuevo)) {
    nd <- as.data.frame(datos[es_nuevo])
    nd$segmento <- factor(segmentos_train[[1L]], levels = segmentos_train)
    nd$barrio <- factor(nd$barrio, levels = barrios_train)
    pred[es_nuevo] <- predict(
      fit,
      newdata = nd,
      type = "response",
      exclude = "s(segmento)"
    )
  }
  as.numeric(pred)
}

metricas_fun <- function(dt) {
  error <- dt$predicho - dt$observado
  sse <- sum(error^2)
  sst <- sum((dt$observado - mean(dt$observado))^2)
  data.table(
    dias = nrow(dt),
    sesgo = mean(error),
    mae = mean(abs(error)),
    rmse = sqrt(mean(error^2)),
    correlacion = cor(dt$observado, dt$predicho),
    r2 = 1 - sse / sst
  )
}

predicciones <- list()
diagnosticos <- list()
parametricos <- list()
suavizados <- list()

for (nombre in names(formulas)) {
  cat("Ajustando", nombre, "\n")
  fit <- bam(
    formulas[[nombre]],
    data = train,
    family = binomial(),
    weights = n_clusters,
    method = "fREML",
    discrete = TRUE,
    nthreads = 2L
  )
  resumen <- summary(fit)
  diagnosticos[[nombre]] <- data.table(
    modelo = nombre,
    convergio = isTRUE(fit$converged),
    AIC = AIC(fit),
    devianza_explicada_train = resumen$dev.expl,
    n_filas_train = nrow(train),
    n_dias_train = uniqueN(train$dia_objetivo)
  )

  tabla_p <- as.data.table(resumen$p.table, keep.rownames = "termino")
  setnames(tabla_p, 2:5, c("estimacion", "error_std", "estadistico", "p_valor"))
  tabla_p[, modelo := nombre]
  parametricos[[nombre]] <- tabla_p

  if (!is.null(resumen$s.table)) {
    tabla_s <- as.data.table(resumen$s.table, keep.rownames = "termino")
    setnames(tabla_s, 2:5, c("edf", "ref_df", "estadistico", "p_valor"))
    tabla_s[, modelo := nombre]
    suavizados[[nombre]] <- tabla_s
  }

  prob <- predecir(fit, base, train)
  pred <- copy(base[, .(
    dia_objetivo, split_modelo, observado, n_clusters,
    viento_max_d1_kmh, viento_faltante_d1
  )])
  pred[, `:=`(modelo = nombre, pred_segmento = n_clusters * prob)]
  predicciones[[nombre]] <- pred[, .(
    observado = sum(observado),
    predicho = sum(pred_segmento),
    viento_max_d1_kmh = first(viento_max_d1_kmh),
    viento_faltante_d1 = first(viento_faltante_d1)
  ), by = .(modelo, split_modelo, dia_objetivo)]
}

pred_dia <- rbindlist(predicciones)
metricas <- rbindlist(list(
  pred_dia[
    split_modelo %in% c("validacion", "test"),
    metricas_fun(.SD),
    by = .(modelo, split_modelo)
  ],
  pred_dia[
    split_modelo %in% c("validacion", "test"),
    metricas_fun(.SD),
    by = modelo
  ][, split_modelo := "validacion + test"]
), use.names = TRUE)

metricas_mensuales <- pred_dia[, metricas_fun(.SD),
  by = .(modelo, mes = format(dia_objetivo, "%Y-%m"))]
cobertura <- unique(base[, .(
  dia_objetivo, split_modelo,
  viento_faltante = viento_faltante_d1 == "1"
)])[, .(
  dias = .N,
  dias_viento_faltante = sum(viento_faltante)
), by = split_modelo]

fwrite(metricas, file.path(path_out, "metricas.csv"))
fwrite(metricas_mensuales, file.path(path_out, "metricas_mensuales.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(cobertura, file.path(path_out, "cobertura_viento.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnosticos_modelos.csv"))
fwrite(rbindlist(parametricos, fill = TRUE), file.path(path_out, "terminos_parametricos.csv"))
fwrite(rbindlist(suavizados, fill = TRUE), file.path(path_out, "terminos_suavizados.csv"))

path_pred_q60 <- file.path(
  "outputs", "modelo_inferencial_segmento_com", "modelo_final_delta",
  "predicciones_diarias.csv"
)
if (file.exists(path_pred_q60)) {
  pred_q60 <- fread(path_pred_q60)
  pred_q60[, dia_objetivo := as.IDate(dia_objetivo)]
  pred_q60 <- pred_q60[
    dia_objetivo >= as.IDate("2026-02-01") &
      dia_objetivo <= as.IDate("2026-05-24")
  ]
  metricas_q60_split <- pred_q60[, metricas_fun(.SD), by = split_modelo]
  metricas_q60_combinadas <- pred_q60[, metricas_fun(.SD)]
  metricas_q60_combinadas[, split_modelo := "validacion + test"]
  metricas_q60 <- rbindlist(
    list(metricas_q60_split, metricas_q60_combinadas),
    use.names = TRUE
  )
  metricas_q60[, modelo := "q60_final_anterior"]
  setcolorder(metricas_q60, names(metricas))
  fwrite(
    rbindlist(list(metricas_q60, metricas), use.names = TRUE),
    file.path(path_out, "metricas_con_q60_anterior.csv")
  )
}

cat("\nCobertura:\n")
print(cobertura)
cat("\nMetricas:")
print(metricas[order(split_modelo, rmse)])
cat("\nTerminos de viento:\n")
print(rbindlist(suavizados, fill = TRUE)[grepl("viento", termino)])
