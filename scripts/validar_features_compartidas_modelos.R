library(arrow)
library(data.table)
library(dplyr)

path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_segmento_dia <- "data/processed/features_compartidas/segmento_dia"
path_calendario <- "data/processed/features_compartidas/calendario_dia.parquet"
path_metadata <- "data/processed/features_compartidas/metadata_features_compartidas.csv"
path_zona_limpia <- "data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia"

base <- as.data.table(as.data.frame(
  arrow::open_dataset(path_segmento_dia, format = "parquet") |>
    dplyr::collect()
))
base[, dia := as.IDate(dia)]

calendario <- as.data.table(arrow::read_parquet(path_calendario))
calendario[, dia := as.IDate(dia)]
metadata <- fread(path_metadata)

if (anyDuplicated(base, by = c("version_cluster", "dia", "barrio", "segmento"))) {
  stop("Hay claves duplicadas en segmento_dia")
}
if (anyDuplicated(calendario$dia)) stop("Hay dias duplicados en calendario_dia")
if (!identical(
  calendario$dia,
  seq(min(calendario$dia), max(calendario$dia), by = "day")
)) {
  stop("El calendario no es continuo")
}

columnas_prohibidas <- grep(
  "split|train|valid|test|temperatura|precipit|lluvia|viento",
  names(base),
  value = TRUE,
  ignore.case = TRUE
)
if (length(columnas_prohibidas)) {
  stop("La base contiene columnas que deben definirse fuera de esta capa: ",
    paste(columnas_prohibidas, collapse = ", "))
}

q_cols <- c("media_q_7", "rms_q_7", "media_q_30", "rms_q_30")
w_cols <- c("media_w_7", "rms_w_7", "media_w_30", "rms_w_30")
if (base[, any(!is.finite(unlist(.SD))), .SDcols = q_cols]) {
  stop("Hay valores no finitos en las propensiones")
}
if (base[, any(unlist(.SD) < 0 | unlist(.SD) > 1), .SDcols = q_cols]) {
  stop("Hay propensiones fuera de [0, 1]")
}
if (base[, any(!is.finite(unlist(.SD)) | unlist(.SD) < 0), .SDcols = w_cols]) {
  stop("Hay ponderaciones operativas invalidas")
}
if (base[, any(rms_q_7 + 1e-12 < media_q_7 | rms_q_30 + 1e-12 < media_q_30)]) {
  stop("Hay RMS de propension menores que sus medias")
}
if (base[, any(!is.finite(porc_nbi_segmento) | !is.finite(densidad_pob_km2))]) {
  stop("Hay valores territoriales faltantes")
}
if (base[, any(n_clusters <= 0L | observado < 0L | observado > n_clusters)]) {
  stop("Hay conteos segmento/dia inconsistentes")
}

fechas_fuente <- as.data.table(as.data.frame(
  arrow::open_dataset(path_features, format = "parquet") |>
    dplyr::summarise(
      fecha_min = min(dia),
      fecha_max = max(dia),
      filas = dplyr::n(),
      clusters = dplyr::n_distinct(cluster_id)
    ) |>
    dplyr::collect()
))

esperada_min <- as.IDate(fechas_fuente$fecha_min) + metadata$rezago_com_dias
if (min(base$dia) != esperada_min || max(base$dia) != as.IDate(fechas_fuente$fecha_max)) {
  stop("La cobertura temporal no coincide con la fuente y el rezago")
}
if (min(calendario$dia) != as.IDate(fechas_fuente$fecha_min) ||
    max(calendario$dia) != as.IDate(fechas_fuente$fecha_max)) {
  stop("La cobertura del calendario no coincide con la fuente")
}
if (!identical(metadata$incluye_splits, FALSE) ||
    !identical(metadata$incluye_clima, FALSE)) {
  stop("Los metadatos no declaran correctamente las exclusiones")
}
if (metadata$filas_cluster_dia_modelables != sum(base$n_clusters) ||
    metadata$observados_modelables != sum(base$observado)) {
  stop("Los metadatos de cobertura no coinciden con segmento_dia")
}

zl <- as.data.table(as.data.frame(
  arrow::open_dataset(path_zona_limpia, format = "parquet") |>
    dplyr::select(version_cluster, cluster_id, dia) |>
    dplyr::collect()
))
zl[, dia := as.IDate(dia)]
if (anyDuplicated(zl, by = c("version_cluster", "cluster_id", "dia"))) {
  stop("Hay claves duplicadas en la comparacion COM-Zona Limpia")
}
if (max(zl$dia) != as.IDate(fechas_fuente$fecha_max)) {
  stop("La comparacion COM-Zona Limpia no llega al corte de las features")
}

resultado <- data.table(
  control = c(
    "clave_segmento_dia",
    "calendario_continuo",
    "rangos_q_w",
    "territorio_completo",
    "sin_splits_ni_clima",
    "cobertura_temporal",
    "objetivo_zl_actualizado"
  ),
  estado = "OK"
)

print(resultado)
print(data.table(
  filas_segmento_dia = nrow(base),
  dias_segmento_dia = uniqueN(base$dia),
  fecha_min_segmento_dia = min(base$dia),
  fecha_max_segmento_dia = max(base$dia),
  filas_calendario = nrow(calendario),
  clusters_fuente = fechas_fuente$clusters,
  filas_comparacion_zl = nrow(zl),
  fecha_max_zl = max(zl$dia)
))
