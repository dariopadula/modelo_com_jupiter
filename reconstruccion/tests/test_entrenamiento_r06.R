# Prueba los dos entrenamientos y su CLI con fixtures pequenas etiquetadas como tales.
# No es una validacion cientifica ni un reentrenamiento de produccion.
script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/")
library_version <- paste0(R.version$major, ".", sub("\\..*$", "", R.version$minor))
user_library <- Sys.getenv("RF_R_LIBRARY", unset = "")
if (!nzchar(user_library) && nzchar(Sys.getenv("USERPROFILE"))) {
  user_library <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "R", "win-library", library_version)
}
if (dir.exists(user_library)) {
  .libPaths(c(user_library, .libPaths()))
}
library(data.table)
source(file.path(root, "R/features/com_receta.R"))
source(file.path(root, "R/features/zl_receta.R"))
source(file.path(root, "R/entrenamiento/com_zl.R"))
reference <- jsonlite::fromJSON(file.path(root, "config/referencia_local_r01.json"))$metadata$com
reference$meses_train <- 202501L
reference$meses_validacion <- 202502L
reference$meses_test <- 202503L
set.seed(7)
com_data <- CJ(cluster_id = paste0("fixture_", 1:8), dia = as.IDate("2025-01-01") + 0:89)
for (column in reference$features_modelo) {
  com_data[, (column) := runif(.N)]
}
com_data[, `:=`(version_cluster = reference$version_cluster,
  anio_mes = as.integer(format(dia, "%Y%m")), n_reclamos = rpois(.N, 0.4),
  dias_historia_observada_cluster = as.integer(dia - min(dia)) + 1L,
  dias_desde_ultimo_reclamo_o_inicio = 1)]
com_data[, tuvo_reclamo := n_reclamos > 0L]

zl_reference <- readRDS(file.path(root, "runtime/r06_zl/modelo_zl.rds"))
zl_sample <- readRDS(file.path(root, "runtime/r06_zl/muestra_zl.rds"))$data
zl_days <- as.IDate(c(outer(c("2025-10-", "2025-11-", "2025-12-", "2026-03-", "2026-04-", "2026-05-"),
  sprintf("%02d", 1:10), paste0)))
zl_data <- rbindlist(lapply(zl_days, function(day) {
  data <- copy(zl_sample)
  data[, `:=`(dia = as.IDate(day), anio_mes = as.integer(format(as.IDate(day), "%Y%m")),
    target_problema_observado = as.integer(seq_len(.N) %% 2L))]
  data
}))
packages <- list(com = list(family = "com", data = com_data, reference = reference),
  zl = list(family = "zl", data = zl_data, reference = zl_reference))
for (family in names(packages)) {
  package <- packages[[family]]
  package$provenance <- list(scope = "fixture_solo_prueba", historical_equivalence = FALSE)
  input_path <- tempfile(paste0("r06_", family), fileext = ".rds")
  output_path <- tempfile(paste0("r06_result_", family))
  saveRDS(package, input_path)
  output <- system2(file.path(R.home("bin"), "Rscript.exe"), c("--vanilla",
    shQuote(file.path(root, "scripts/entrenar_modelo.R")), shQuote(input_path), shQuote(output_path)),
    stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(output, "status"))) {
    stop(paste(output, collapse = "\n"))
  }
  result <- readRDS(file.path(output_path, "resultado.rds"))
  stopifnot(result$status == "candidato_no_promovido", nrow(result$metrics) == 3L,
    all(is.finite(result$predictions$pred_prob)), all(result$predictions$pred_prob >= 0),
    all(result$predictions$pred_prob <= 1), file.exists(file.path(output_path, "splits.csv")))
  if (family == "zl") {
    stopifnot(result$predictions[, uniqueN(split), by = dia][, all(V1 == 1L)])
  }
  cat("R06_TRAINING_FIXTURE_OK:", family, "\n")

  # Comprueba tambien el puente Arrow en un legado ficticio pequeno.
  legacy_fixture <- tempfile(paste0("r06_legacy_", family))
  features_path <- file.path(legacy_fixture, "data/processed/modelo_cluster_dia/features_cluster_dia")
  dir.create(features_path, recursive = TRUE)
  arrow::write_dataset(package$data, features_path, format = "parquet")
  expected_rows <- nrow(package$data)
  if (family == "zl") {
    comparison <- package$data[, .(version_cluster, cluster_id, dia, anio_mes,
      hay_zl_visita_efectiva = TRUE, hay_zl_voluminosos = FALSE,
      hay_zl_problema_comparable = target_problema_observado == 1L)]
    comparison[1L, hay_zl_voluminosos := TRUE]
    comparison[2L, hay_zl_visita_efectiva := FALSE]
    comparison_path <- file.path(legacy_fixture, "data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia")
    dir.create(comparison_path, recursive = TRUE)
    arrow::write_dataset(comparison, comparison_path, format = "parquet")
    segment_fields <- c("version_cluster", "cluster_id", "porc_nbi_segmento",
      "porc_asentamiento_nbi_segmento", "porc_vivienda_inadecuada_segmento",
      "densidad_pob_km2", "cluster_multisegmento", "pct_posiciones_segmento_principal")
    segments <- unique(package$data[, ..segment_fields])
    segments_path <- file.path(legacy_fixture, "data/processed/cluster_territorial/cluster_segmento_censal")
    dir.create(segments_path, recursive = TRUE)
    arrow::write_dataset(segments, segments_path, format = "parquet")
    holiday_directory <- file.path(legacy_fixture, "data/reference/feriados")
    dir.create(holiday_directory, recursive = TRUE)
    writeLines("diasDesc <- as.Date(character())", file.path(holiday_directory, "feriados.R"))
    expected_rows <- expected_rows - 2L
  }
  imported_path <- tempfile(paste0("r06_imported_", family), fileext = ".rds")
  output <- system2(file.path(R.home("bin"), "Rscript.exe"), c("--vanilla",
    shQuote(file.path(root, "herramientas_migracion/preparar_entrenamiento_r06.R")),
    family, shQuote(legacy_fixture), shQuote(imported_path)), stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(output, "status"))) {
    stop(paste(output, collapse = "\n"))
  }
  imported <- readRDS(imported_path)
  stopifnot(imported$family == family, nrow(imported$data) == expected_rows)
  cat("R06_IMPORT_FIXTURE_OK:", family, "\n")
}
