# Importa el bundle ZL efectivo y ocho filas de referencia mediante filtros Arrow.
# Entrada: raiz del repositorio anterior. Salidas nuevas: bundle y muestra en runtime.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L) {
  stop("Uso: importar_referencia_zl_r06.R <raiz_repositorio_original>")
}

script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
reconstruction_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
legacy_root <- normalizePath(arguments[[1L]], winslash = "/", mustWork = TRUE)
library_version <- paste0(R.version$major, ".", sub("\\..*$", "", R.version$minor))
user_library <- Sys.getenv("RF_R_LIBRARY", unset = Sys.getenv("R_LIBS_USER", unset = ""))
if ((!nzchar(user_library) || !dir.exists(user_library)) && identical(Sys.info()[["sysname"]], "Windows") &&
    nzchar(Sys.getenv("USERPROFILE"))) {
  user_library <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "R", "win-library", library_version)
}
if (nzchar(user_library) && dir.exists(user_library)) {
  .libPaths(c(user_library, .libPaths()))
}

library(arrow)
library(data.table)
library(jsonlite)
source(file.path(reconstruction_root, "R/features/zl_receta.R"))
source(file.path(reconstruction_root, "R/modelos/zl_xgboost.R"))

reference_id <- "random_dia_estratificado_mes"
model_source_relative <- "data/processed/modelos/experimentos_cascada_zl/operativo_segmento/modelo_zl_xgboost.rds"
model_source_path <- file.path(legacy_root, model_source_relative)
prediction_source_path <- file.path(reconstruction_root, "runtime/referencia_r01/muestra_predicciones.csv")
holiday_source_path <- file.path(legacy_root, "data/reference/feriados/feriados.R")
for (required_path in c(model_source_path, prediction_source_path, holiday_source_path)) {
  if (!file.exists(required_path)) {
    stop("Falta una fuente R06 requerida: ", required_path)
  }
}

bundle_source <- readRDS(model_source_path)
if (!identical(bundle_source$feature_set_zl, "operativo_segmento") || !reference_id %in% names(bundle_source)) {
  stop("La referencia local no contiene el escenario ZL congelado esperado")
}
scenario <- bundle_source[[reference_id]]
scenario_parameters <- bundle_source$parametros[escenario == reference_id]
if (nrow(scenario_parameters) != 1L) {
  stop("No se pudo identificar una fila unica de parametros ZL")
}
model <- list(
  model_id = "zl_problema",
  model_version = "xgboost_operativo_segmento_random_dia_estratificado_mes",
  version_cluster = as.character(scenario_parameters$version_cluster[[1L]]),
  scenario = reference_id,
  random_dia_estratificado_mes = scenario,
  feature_set_zl = bundle_source$feature_set_zl,
  features_numericas = bundle_source$features_numericas,
  features_categoricas = bundle_source$features_categoricas,
  parametros = scenario_parameters,
  fit = scenario$fit,
  prep = scenario$prep
)
manifest_path <- file.path(reconstruction_root, "config/referencia_local_r01.json")
manifest <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)
source_manifests <- Filter(function(file) identical(file$path, model_source_relative), manifest$files)
if (length(source_manifests) != 1L || is.null(source_manifests[[1L]]$sha256)) {
  stop("La referencia R01 no registra hash para el modelo ZL efectivo")
}
source_manifest <- source_manifests[[1L]]

sample_predictions <- data.table::fread(prediction_source_path, encoding = "UTF-8")
sample_predictions <- sample_predictions[modelo_id == "zl_problema"]
if (nrow(sample_predictions) != 8L || data.table::uniqueN(sample_predictions$dia_objetivo) != 1L) {
  stop("La muestra R01 no corresponde a ocho predicciones ZL de un dia")
}
sample_day <- as.Date(sample_predictions$dia_objetivo[[1L]])
sample_ids <- as.character(sample_predictions$cluster_id)

raw_feature_names <- setdiff(model$features_numericas, c(
  "exceso_min_tiempo_periodo_pred_pos", "exceso_mean_tiempo_periodo_pred_pos",
  "exceso_max_tiempo_periodo_pred_pos", "exceso_min_tiempo_periodo_pred_trunc7",
  "exceso_mean_tiempo_periodo_pred_trunc7", "exceso_max_tiempo_periodo_pred_trunc7",
  "porc_nbi_segmento", "porc_asentamiento_nbi_segmento", "porc_vivienda_inadecuada_segmento",
  "densidad_pob_km2", "cluster_multisegmento", "pct_posiciones_segmento_principal",
  "dia_semana", "fin_de_semana", "es_feriado", "vispera_feriado", "dia_habil"
))
feature_dataset <- arrow::open_dataset(file.path(legacy_root, "data/processed/modelo_cluster_dia/features_cluster_dia"),
  format = "parquet")
sample_features <- data.table::as.data.table(dplyr::collect(dplyr::select(
  dplyr::filter(feature_dataset, cluster_id %in% sample_ids, dia == sample_day,
    version_cluster == model$version_cluster),
  dplyr::all_of(c("cluster_id", "dia", "anio_mes", "version_cluster", raw_feature_names))
)))
if (nrow(sample_features) != length(sample_ids)) {
  stop("Las features COM no cubren exactamente los ocho clusters de muestra")
}

segment_dataset <- arrow::open_dataset(file.path(legacy_root, "data/processed/cluster_territorial/cluster_segmento_censal"),
  format = "parquet")
sample_segments <- data.table::as.data.table(dplyr::collect(dplyr::filter(segment_dataset,
  cluster_id %in% sample_ids, version_cluster == model$version_cluster)))
holiday_environment <- new.env(parent = baseenv())
sys.source(holiday_source_path, envir = holiday_environment)
if (!exists("diasDesc", envir = holiday_environment, inherits = FALSE)) {
  stop("El calendario de feriados no define diasDesc")
}

sample_features <- rf_prepare_zl_features(sample_features, sample_segments,
  holiday_environment$diasDesc, model$features_numericas)
sample_predictions <- sample_predictions[, .(cluster_id, dia_objetivo, pred_prob)]
sample_data <- merge(sample_features, sample_predictions,
  by.x = c("cluster_id", "dia"), by.y = c("cluster_id", "dia_objetivo"), all = FALSE, sort = FALSE)
if (nrow(sample_data) != 8L) {
  stop("No se pudo enlazar la prediccion congelada con las features reconstruidas")
}

output_directory <- file.path(reconstruction_root, "runtime/r06_zl")
model_output_path <- file.path(output_directory, "modelo_zl.rds")
sample_output_path <- file.path(output_directory, "muestra_zl.rds")
manifest_path <- file.path(reconstruction_root, "config/referencia_local_r01.json")
provenance_path <- file.path(reconstruction_root, "config/procedencia_r06_zl.json")
if (file.exists(model_output_path) || file.exists(sample_output_path) || file.exists(provenance_path)) {
  stop("Ya existe una salida R06; conservarla y elegir una ruta nueva para la importacion")
}
dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
saveRDS(model, model_output_path)
saveRDS(list(data = sample_data, reference_id = reference_id), sample_output_path)

provenance <- list(
  reference_id = manifest$reference_id,
  source_model = model_source_relative,
  source_sha256 = source_manifest$sha256,
  imported_bundle = "runtime/r06_zl/modelo_zl.rds",
  imported_sample = "runtime/r06_zl/muestra_zl.rds",
  scenario = reference_id,
  sample_day = as.character(sample_day),
  sample_rows = nrow(sample_data),
  model_numeric_features = model$features_numericas,
  model_categorical_features = model$features_categoricas
)
jsonlite::write_json(provenance, provenance_path, auto_unbox = TRUE, pretty = TRUE)
cat("R06_ZL_REFERENCE_IMPORTED:", nrow(sample_data), "filas para", as.character(sample_day), "\n")
