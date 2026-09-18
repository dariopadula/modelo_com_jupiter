library(arrow)
library(data.table)

fun <- dir("funciones/", pattern = ".R", ignore.case = TRUE)
for (ii in fun) source(file.path("funciones", ii))
source("zona_limpia/funciones_zona_limpia.R")

path_com_completo <- "data/parquet/com_completo"
path_levante <- "data/parquet/levante"
path_cluster_actual <- "data/processed/cluster_update_check/contenedor_posicion_cluster_actual"
path_com_cluster_dia <- "data/processed/modelo_cluster_dia/com_cluster_dia"

out_processed <- "data/processed/zona_limpia"
out_outputs <- "zona_limpia/outputs"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
redondeo_m <- 1
umbral_asignacion_m <- 50
umbral_revision_m <- 100
usar_solo_contenedor_dia_elegible_modelo <- TRUE
estados_asignacion_validos <- c("asignado", "revision")

dir.create(out_processed, recursive = TRUE, showWarnings = FALSE)
dir.create(out_outputs, recursive = TRUE, showWarnings = FALSE)

datos_com_completo <- as.data.table(arrow::open_dataset(path_com_completo, format = "parquet"))
datos_levante <- as.data.table(arrow::open_dataset(path_levante, format = "parquet"))
contenedor_posicion_cluster <- as.data.table(
  arrow::open_dataset(path_cluster_actual, format = "parquet")
)
com_cluster_dia <- as.data.table(arrow::open_dataset(path_com_cluster_dia, format = "parquet"))

if (!is.na(target_version_cluster) && target_version_cluster != "") {
  contenedor_posicion_cluster <- contenedor_posicion_cluster[version_cluster == target_version_cluster]
  com_cluster_dia <- com_cluster_dia[version_cluster == target_version_cluster]
} else {
  versiones <- sort(unique(contenedor_posicion_cluster$version_cluster))
  target_version_cluster <- versiones[length(versiones)]
  contenedor_posicion_cluster <- contenedor_posicion_cluster[version_cluster == target_version_cluster]
  com_cluster_dia <- com_cluster_dia[version_cluster == target_version_cluster]
}

if (nrow(contenedor_posicion_cluster) == 0L) {
  stop("No hay mapeo contenedor-cluster para version_cluster = ", target_version_cluster)
}
if (nrow(com_cluster_dia) == 0L) {
  stop("No hay COM cluster-dia para version_cluster = ", target_version_cluster)
}

zl <- datos_com_completo[es_zona_limpia == TRUE]
zl <- filtrar_periodo_analisis_zona_limpia(zl)
cols_zl_req <- c("id", "dia", "x", "y", "incidente_zona_limpia_mapeado", "tipo_zona_limpia")
if (!all(cols_zl_req %in% names(zl))) {
  stop("com_completo debe tener columnas: ", paste(cols_zl_req, collapse = ", "))
}

zl <- agregar_indicadores_zona_limpia(zl)
zl_asignar <- data.table::copy(zl)
zl_asignar[, incidente := incidente_zona_limpia_mapeado]

res_zl <- asignar_com_a_contenedores_activos(
  datos_com = zl_asignar,
  datos_levante = datos_levante,
  contenedor_posicion_cluster = contenedor_posicion_cluster,
  redondeo_m = redondeo_m,
  umbral_asignacion_m = umbral_asignacion_m,
  umbral_revision_m = umbral_revision_m,
  usar_solo_contenedor_dia_elegible_modelo = usar_solo_contenedor_dia_elegible_modelo
)

asignaciones_zl <- res_zl$asignaciones_com
setnames(asignaciones_zl, "estado_asignacion_com", "estado_asignacion_zl")
asignaciones_zl[, version_cluster := target_version_cluster]

zl_meta <- unique(zl[, .(
  id,
  incidente_zona_limpia_normalizado,
  incidente_zona_limpia_mapeado,
  tipo_zona_limpia,
  es_zl_problema_comparable,
  es_zl_voluminosos,
  es_zl_limpio,
  es_zl_no_visitado,
  es_zl_no_encontrado,
  es_zl_no_realizado,
  es_zl_visita_efectiva
)])

asignaciones_zl <- zl_meta[
  asignaciones_zl,
  on = "id"
]

asignaciones_zl[, `:=`(
  anio = as.integer(format(dia, "%Y")),
  anio_mes = as.integer(format(dia, "%Y%m"))
)]

zl_validas_cluster <- asignaciones_zl[
  estado_asignacion_zl %in% estados_asignacion_validos & !is.na(cluster_id)
]

zl_cluster_dia <- zl_validas_cluster[
  ,
  .(
    n_zl = uniqueN(id),
    n_zl_asignado = uniqueN(id[estado_asignacion_zl == "asignado"]),
    n_zl_revision = uniqueN(id[estado_asignacion_zl == "revision"]),
    n_zl_visitas_efectivas = uniqueN(id[es_zl_visita_efectiva == TRUE]),
    n_zl_problema_comparable = uniqueN(id[es_zl_problema_comparable == TRUE]),
    n_zl_basura_fuera = uniqueN(id[tipo_zona_limpia == "basura_fuera"]),
    n_zl_contenedor_desbordado = uniqueN(id[tipo_zona_limpia == "contenedor_desbordado"]),
    n_zl_voluminosos = uniqueN(id[es_zl_voluminosos == TRUE]),
    n_zl_limpio = uniqueN(id[es_zl_limpio == TRUE]),
    n_zl_no_visitado = uniqueN(id[es_zl_no_visitado == TRUE]),
    n_zl_no_encontrado = uniqueN(id[es_zl_no_encontrado == TRUE]),
    n_zl_no_realizado = uniqueN(id[es_zl_no_realizado == TRUE]),
    distancia_zl_mediana_m = median(distancia_m, na.rm = TRUE),
    distancia_zl_p90_m = as.numeric(quantile(distancia_m, 0.9, na.rm = TRUE))
  ),
  by = .(cluster_id, dia)
]

zl_cluster_dia[, `:=`(
  hay_zl = n_zl > 0,
  hay_zl_visita_efectiva = n_zl_visitas_efectivas > 0,
  hay_zl_problema_comparable = n_zl_problema_comparable > 0,
  hay_zl_voluminosos = n_zl_voluminosos > 0,
  hay_zl_limpio = n_zl_limpio > 0,
  hay_zl_sin_validacion = (n_zl_no_visitado + n_zl_no_encontrado + n_zl_no_realizado) > 0
)]
zl_cluster_dia[, `:=`(
  anio = as.integer(format(dia, "%Y")),
  anio_mes = as.integer(format(dia, "%Y%m")),
  version_cluster = target_version_cluster
)]

com_comp <- data.table::copy(com_cluster_dia)
com_comp[, `:=`(
  hay_com = n_reclamos > 0,
  anio = NULL,
  anio_mes = NULL,
  version_cluster = NULL
)]

comparacion <- merge(
  com_comp,
  zl_cluster_dia[, !"version_cluster"],
  by = c("cluster_id", "dia"),
  all = TRUE
)

cols_n <- grep("^(n_reclamos|n_zl)", names(comparacion), value = TRUE)
for (col in cols_n) {
  comparacion[is.na(get(col)), (col) := 0L]
}

cols_log <- c(
  "tuvo_reclamo",
  "hay_com",
  "hay_zl",
  "hay_zl_visita_efectiva",
  "hay_zl_problema_comparable",
  "hay_zl_voluminosos",
  "hay_zl_limpio",
  "hay_zl_sin_validacion"
)
for (col in cols_log) {
  if (!col %in% names(comparacion)) comparacion[, (col) := FALSE]
  comparacion[is.na(get(col)), (col) := FALSE]
}

comparacion[, estado_comparacion := clasificar_comparacion_com_zona_limpia(
  hay_com = hay_com,
  hay_zl_problema_comparable = hay_zl_problema_comparable,
  hay_zl_voluminosos = hay_zl_voluminosos,
  hay_zl_limpio = hay_zl_limpio,
  hay_zl_visita_efectiva = hay_zl_visita_efectiva,
  hay_zl_sin_validacion = hay_zl_sin_validacion
)]

comparacion[, `:=`(
  universo_comparable_zl = hay_zl_visita_efectiva,
  anio = as.integer(format(dia, "%Y")),
  anio_mes = as.integer(format(dia, "%Y%m")),
  version_cluster = target_version_cluster
)]

resumen_estado <- comparacion[
  ,
  .(
    n_cluster_dia = .N,
    n_com = sum(n_reclamos),
    n_zl = sum(n_zl),
    n_zl_problema_comparable = sum(n_zl_problema_comparable),
    n_zl_voluminosos = sum(n_zl_voluminosos)
  ),
  by = estado_comparacion
][order(-n_cluster_dia)]

resumen_estado_universo_comparable <- comparacion[
  universo_comparable_zl == TRUE,
  .(
    n_cluster_dia = .N,
    n_com = sum(n_reclamos),
    n_zl = sum(n_zl),
    n_zl_problema_comparable = sum(n_zl_problema_comparable),
    n_zl_voluminosos = sum(n_zl_voluminosos)
  ),
  by = estado_comparacion
][order(-n_cluster_dia)]

resumen_mensual <- comparacion[
  ,
  .(
    n_cluster_dia = .N,
    n_com = sum(n_reclamos),
    n_zl = sum(n_zl),
    n_zl_visitas_efectivas = sum(n_zl_visitas_efectivas),
    n_zl_problema_comparable = sum(n_zl_problema_comparable),
    n_zl_voluminosos = sum(n_zl_voluminosos)
  ),
  by = .(anio_mes, estado_comparacion)
][order(anio_mes, estado_comparacion)]

resumen_mensual_universo_comparable <- comparacion[
  universo_comparable_zl == TRUE,
  .(
    n_cluster_dia = .N,
    n_com = sum(n_reclamos),
    n_zl = sum(n_zl),
    n_zl_visitas_efectivas = sum(n_zl_visitas_efectivas),
    n_zl_problema_comparable = sum(n_zl_problema_comparable),
    n_zl_voluminosos = sum(n_zl_voluminosos)
  ),
  by = .(anio_mes, estado_comparacion)
][order(anio_mes, estado_comparacion)]

resumen_cluster <- comparacion[
  ,
  .(
    n_dias_con_evento = .N,
    n_dias_com = sum(hay_com),
    n_dias_zl = sum(hay_zl),
    n_dias_ambos_problema = sum(estado_comparacion == "ambos_reportan_problema"),
    n_dias_solo_zl_problema = sum(estado_comparacion == "solo_zona_limpia_problema"),
    n_dias_solo_com_zl_limpio = sum(estado_comparacion == "solo_com_zl_limpio"),
    n_com = sum(n_reclamos),
    n_zl = sum(n_zl),
    n_zl_problema_comparable = sum(n_zl_problema_comparable),
    n_zl_voluminosos = sum(n_zl_voluminosos)
  ),
  by = cluster_id
][order(-n_dias_solo_zl_problema, -n_dias_ambos_problema, -n_com)]

arrow::write_dataset(
  asignaciones_zl,
  path = file.path(out_processed, "asignaciones_zona_limpia"),
  format = "parquet",
  partitioning = c("version_cluster", "anio", "anio_mes"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

arrow::write_dataset(
  zl_cluster_dia,
  path = file.path(out_processed, "zona_limpia_cluster_dia"),
  format = "parquet",
  partitioning = c("version_cluster", "anio", "anio_mes"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

arrow::write_dataset(
  comparacion,
  path = file.path(out_processed, "comparacion_com_zona_limpia_cluster_dia"),
  format = "parquet",
  partitioning = c("version_cluster", "anio", "anio_mes"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

fwrite(resumen_estado, file.path(out_outputs, "comparacion_com_zona_limpia_resumen_estado.csv"))
fwrite(
  resumen_estado_universo_comparable,
  file.path(out_outputs, "comparacion_com_zona_limpia_resumen_estado_universo_comparable.csv")
)
fwrite(resumen_mensual, file.path(out_outputs, "comparacion_com_zona_limpia_resumen_mensual.csv"))
fwrite(
  resumen_mensual_universo_comparable,
  file.path(out_outputs, "comparacion_com_zona_limpia_resumen_mensual_universo_comparable.csv")
)
fwrite(resumen_cluster, file.path(out_outputs, "comparacion_com_zona_limpia_resumen_cluster.csv"))

print(data.table(
  version_cluster = target_version_cluster,
  filas_comparacion = nrow(comparacion),
  clusters = uniqueN(comparacion$cluster_id),
  dias = uniqueN(comparacion$dia)
))
print(resumen_estado)
print(resumen_estado_universo_comparable)
