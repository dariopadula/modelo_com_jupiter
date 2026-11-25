# Importa solo columnas y periodos de las familias efectivas a un paquete propio.
# Corrida completa a cargo del usuario; no entrena ni modifica fuentes originales.
# Uso: Rscript preparar_entrenamiento_r06.R <com|zl> <raiz_original> <salida_nueva.rds>

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 3L || !arguments[[1L]] %in% c("com", "zl")) {
  stop("Uso: preparar_entrenamiento_r06.R <com|zl> <raiz_original> <salida_nueva.rds>")
}
script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/")
legacy_root <- normalizePath(arguments[[2L]], winslash = "/", mustWork = TRUE)
output_path <- arguments[[3L]]
if (file.exists(output_path)) {
  stop("La salida ya existe; elegir una ruta nueva")
}
library_version <- paste0(R.version$major, ".", sub("\\..*$", "", R.version$minor))
user_library <- Sys.getenv("RF_R_LIBRARY", unset = "")
if (!nzchar(user_library) && nzchar(Sys.getenv("USERPROFILE"))) {
  user_library <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "R", "win-library", library_version)
}
if (dir.exists(user_library)) {
  .libPaths(c(user_library, .libPaths()))
}
library(data.table)
source(file.path(root, "R/features/zl_receta.R"))
manifest <- jsonlite::fromJSON(file.path(root, "config/referencia_local_r01.json"))
family <- arguments[[1L]]
keys <- c("version_cluster", "cluster_id", "dia", "anio_mes")
dataset_path <- "data/processed/modelo_cluster_dia/features_cluster_dia"
dataset <- arrow::open_dataset(file.path(legacy_root, dataset_path), format = "parquet")

if (family == "com") {
  reference <- manifest$metadata$com
  target_version <- reference$version_cluster
  last_month <- max(reference$meses_test)
  derived <- c("historia_observada_7_29", "historia_observada_30_89",
    "historia_observada_90_179", "historia_observada_180_mas",
    "dias_desde_ultimo_reclamo_o_inicio_trunc_90")
  columns <- unique(c(keys, setdiff(reference$features_modelo, derived),
    "n_reclamos", "tuvo_reclamo", "dias_historia_observada_cluster",
    "dias_desde_ultimo_reclamo_o_inicio"))
  data <- as.data.table(dplyr::collect(dplyr::select(
    dplyr::filter(dataset, version_cluster == target_version, anio_mes <= last_month),
    dplyr::all_of(columns))))
  source_paths <- dataset_path
} else {
  reference <- readRDS(file.path(root, "runtime/r06_zl/modelo_zl.rds"))
  target_version <- reference$version_cluster
  selected_months <- as.integer(strsplit(reference$parametros$meses_modelo[[1L]], ",", fixed = TRUE)[[1L]])
  territorial <- c("porc_nbi_segmento", "porc_asentamiento_nbi_segmento",
    "porc_vivienda_inadecuada_segmento", "densidad_pob_km2", "cluster_multisegmento",
    "pct_posiciones_segmento_principal")
  calendar <- c("dia_semana", "fin_de_semana", "es_feriado", "vispera_feriado", "dia_habil")
  derived <- grep("^exceso_", reference$features_numericas, value = TRUE)
  columns <- c(keys, setdiff(reference$features_numericas, c(territorial, calendar, derived)))
  features <- as.data.table(dplyr::collect(dplyr::select(
    dplyr::filter(dataset, version_cluster == target_version, anio_mes %in% selected_months),
    dplyr::all_of(columns))))
  comparison_path <- "data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia"
  comparison_dataset <- arrow::open_dataset(file.path(legacy_root, comparison_path), format = "parquet")
  label_columns <- c(keys, "hay_zl_visita_efectiva", "hay_zl_voluminosos", "hay_zl_problema_comparable")
  comparison <- as.data.table(dplyr::collect(dplyr::select(
    dplyr::filter(comparison_dataset, version_cluster == target_version,
      anio_mes %in% selected_months, hay_zl_visita_efectiva == TRUE, hay_zl_voluminosos == FALSE),
    dplyr::all_of(label_columns))))
  segment_path <- "data/processed/cluster_territorial/cluster_segmento_censal"
  segment_dataset <- arrow::open_dataset(file.path(legacy_root, segment_path), format = "parquet")
  segments <- as.data.table(dplyr::collect(dplyr::select(
    dplyr::filter(segment_dataset, version_cluster == target_version),
    dplyr::all_of(c("version_cluster", "cluster_id", territorial)))))
  holidays_path <- "data/reference/feriados/feriados.R"
  holiday_environment <- new.env(parent = baseenv())
  sys.source(file.path(legacy_root, holidays_path), holiday_environment)
  features <- rf_prepare_zl_features(features, segments, holiday_environment$diasDesc,
    reference$features_numericas)
  data <- rf_prepare_zl_training_data(features, comparison, reference$features_numericas, selected_months)
  source_paths <- c(dataset_path, comparison_path, segment_path, holidays_path)
}

if (!nrow(data)) {
  stop("El paquete de entrenamiento quedo vacio")
}
provenance <- list(reference_id = manifest$reference_id, family = family,
  sources = source_paths, rows = nrow(data),
  date_min = as.character(min(data$dia)), date_max = as.character(max(data$dia)),
  note = "Snapshot local actual; no demuestra identidad con insumos historicos publicados")
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
saveRDS(list(family = family, data = data, reference = reference, provenance = provenance), output_path)
cat("R06_TRAINING_INPUT_OK: family=", family, " rows=", nrow(data),
  " output=", output_path, "\n", sep = "")
