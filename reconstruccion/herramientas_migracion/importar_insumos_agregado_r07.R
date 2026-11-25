# Importa canonicos y referencias para reconstruir A0/P3 sin publicaciones de la app.
# Corrida completa a cargo del usuario; no modifica datos ni modelos originales.
# Uso: importar_insumos_agregado_r07.R <raiz_original> <fecha_hasta> <salida_nueva.rds>
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 3L) {
  stop("Uso: importar_insumos_agregado_r07.R <raiz_original> <fecha_hasta> <salida_nueva.rds>")
}
script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/")
source(file.path(root, "R/configuracion/runtime_r07.R"), encoding = "UTF-8")
rf_init_r07()
library(data.table)
legacy <- normalizePath(arguments[[1L]], winslash = "/", mustWork = TRUE)
until <- as.Date(arguments[[2L]])
if (file.exists(arguments[[3L]]) || is.na(until) || until > as.Date("2026-05-31")) {
  stop("Se requiere salida nueva y fecha historica hasta mayo 2026; no abrir T032")
}
manifest <- jsonlite::fromJSON(file.path(root, "config/referencia_local_r01.json"))
spatial_version <- manifest$cluster_version
feature_path <- "data/processed/modelo_cluster_dia/features_cluster_dia"
dataset <- arrow::open_dataset(file.path(legacy, feature_path), format = "parquet")
columns <- c("version_cluster", "cluster_id", "dia", "tuvo_reclamo",
  "mean_tiempo_desde_ultimo_levante_pred", "mean_levante_periodo", "mean_ratio_tiempo_periodo_pred")
features <- as.data.table(dplyr::collect(dplyr::select(dplyr::filter(dataset,
  version_cluster == spatial_version, dia <= until, cluster_existente_dia == TRUE), dplyr::all_of(columns))))
admin_path <- "data/processed/cluster_territorial/cluster_admin_territorial"
segment_path <- "data/processed/cluster_territorial/cluster_segmento_censal"
admin <- as.data.table(dplyr::collect(dplyr::select(dplyr::filter(
  arrow::open_dataset(file.path(legacy, admin_path)), version_cluster == spatial_version),
  version_cluster, cluster_id, nombre_barrio_ine)))
segments <- as.data.table(dplyr::collect(dplyr::select(dplyr::filter(
  arrow::open_dataset(file.path(legacy, segment_path)), version_cluster == spatial_version),
  version_cluster, cluster_id, codseg_centroide)))
setnames(admin, "nombre_barrio_ine", "barrio")
setnames(segments, "codseg_centroide", "segmento")
geography <- merge(admin, segments, by = c("version_cluster", "cluster_id"), all.x = TRUE, sort = FALSE)
holidays <- new.env(parent = baseenv())
sys.source(file.path(legacy, "data/reference/feriados/feriados.R"), holidays)
calendar <- list(train = manifest$metadata$com$meses_train, valid = manifest$metadata$com$meses_validacion,
  test = manifest$metadata$com$meses_test)
package <- list(features = features, geography = geography, calendar = calendar,
  holidays = as.IDate(holidays$diasDesc), provenance = list(reference_id = manifest$reference_id,
    sources = c(feature_path, admin_path, segment_path), history_until = as.character(until),
    observation_status = "snapshot_historico_no_certifica_cierre_operativo"))
dir.create(dirname(arguments[[3L]]), recursive = TRUE, showWarnings = FALSE)
saveRDS(package, arguments[[3L]])
cat("R07_INPUT_OK: rows=", nrow(features), " sin_dependencia_app\n", sep = "")
