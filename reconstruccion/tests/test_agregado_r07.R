# Regresion A0/P3 fija y comparacion de features contra bloques originales en fixtures.
# Entrena un compuesto pequeno para verificar OOF, seleccion/refit y CLI sin corrida completa.
arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/")
legacy <- normalizePath(file.path(root, ".."), winslash = "/")
source(file.path(root, "R/configuracion/runtime_r07.R"), encoding = "UTF-8")
rf_init_r07()
library(data.table)
source(file.path(root, "R/features/agregado_receta.R"), encoding = "UTF-8")
source(file.path(root, "R/modelos/agregado_a0_p3.R"), encoding = "UTF-8")

sample <- readRDS(file.path(root, "runtime/r07_agregado/muestra.rds"))
bundle <- readRDS(file.path(root, "runtime/r07_agregado/bundle.rds"))
sample$base[, version_cluster := bundle$version_cluster]
stopifnot(max(abs(rf_predict_a0(sample$base, bundle$a0) - sample$base$prob_a0)) < 1e-10)
prediction <- rf_score_aggregate(sample$base, bundle)
daily <- merge(prediction$montevideo, sample$daily_reference,
  by = c("dia_objetivo", "escenario", "split_modelo"), suffixes = c("_new", "_ref"))
neighborhood <- merge(prediction$barrio, sample$neighborhood_reference,
  by = c("dia_objetivo", "escenario", "split_modelo", "barrio"), suffixes = c("_new", "_ref"))
stopifnot(nrow(daily) == nrow(prediction$montevideo), nrow(neighborhood) == nrow(prediction$barrio),
  max(abs(daily$predicho_new - daily$predicho_ref)) < 1e-6,
  max(abs(neighborhood$predicho_new - neighborhood$predicho_ref)) < 1e-6,
  identical(daily$observado_new, daily$observado_ref),
  identical(neighborhood$n_clusters_new, neighborhood$n_clusters_ref))
cat("R07_FIXED_PARITY_OK: segments=", nrow(sample$base), " barrios=", nrow(neighborhood),
  " max_daily_difference=", max(abs(daily$predicho_new - daily$predicho_ref)), "\n", sep = "")

set.seed(19)
features <- CJ(cluster_id = paste0("fixture_", sprintf("%02d", 1:12)),
  dia = seq(as.IDate("2025-01-01"), as.IDate("2026-05-24"), by = "day"))
features[, `:=`(version_cluster = "fixture_v1", tuvo_reclamo = rbinom(.N, 1L, 0.2),
  mean_tiempo_desde_ultimo_levante_pred = runif(.N, 0.2, 5), mean_levante_periodo = 2)]
features[, mean_ratio_tiempo_periodo_pred := mean_tiempo_desde_ultimo_levante_pred / mean_levante_periodo]
geography <- data.table(cluster_id = unique(features$cluster_id), version_cluster = "fixture_v1",
  barrio = rep(c("barrio_a", "barrio_b", "barrio_c"), each = 4L),
  segmento = rep(as.character(1:6), each = 2L))
calendar <- list(train = 202501:202512, valid = 202601:202603, test = 202604:202605)
holidays <- as.IDate("2026-05-01")
prepared <- rf_build_aggregate(features, geography, calendar, holidays)
prepared$provenance <- list(scope = "fixture_solo_prueba", historic_equivalence = FALSE)

# Ejecuta solo los bloques puros del legado en memoria, con los mismos insumos.
source_rows <- geography[features, on = c("version_cluster", "cluster_id")]
setnames(source_rows, "dia", "dia_objetivo")
source_rows[, y := as.integer(tuvo_reclamo)]
old <- new.env(parent = globalenv())
old$datos <- copy(source_rows)
old$ventana <- 90L
old$rezago <- 2L
old$fuerza_prior_barrio <- 30
old$tope_exceso <- 3
expressions <- parse(file.path(legacy, "scripts/explorar_carga_atraso_ponderada_propension_com.R"), encoding = "UTF-8")
texts <- vapply(expressions, function(expression) paste(deparse(expression), collapse = " "), character(1))
start <- grep("^setorder\\(datos", texts)
end <- grep("^modelo <- readRDS", texts)
stopifnot(length(start) == 1L, length(end) == 1L)
for (index in seq.int(start, end - 1L)) {
  eval(expressions[[index]], old)
}
eval(expressions[[grep("^resumir_nivel <- function", texts)]], old)
old$datos[, split_modelo := fifelse(dia_objetivo <= as.IDate("2025-12-31"), "entrenamiento",
  fifelse(dia_objetivo <= as.IDate("2026-03-31"), "validacion", "test"))]
auditables <- old$datos[is.finite(q_cluster_90_eb) & is.finite(h_exceso)]
anchor <- old$resumir_nivel(auditables, c("dia_objetivo", "barrio", "segmento"), "segmento")
finite_columns <- c("media_tiempo_levante", "media_periodo", "media_ratio", "media_h",
  "prop_exceso_positivo", "prop_exceso_mayor_1", "media_q", "rms_q", "media_w", "rms_w")
anchor <- anchor[Reduce(`&`, lapply(anchor[, ..finite_columns], is.finite)),
  .(dia_objetivo, barrio, segmento)]

original <- new.env(parent = globalenv())
original$datos <- copy(source_rows)
original$ventanas <- c(7L, 15L, 30L, 60L, 90L)
original$rezago <- 2L
original$fuerza_prior_barrio <- 30
original$fuerza_prior_global <- 200
original$tope_exceso <- 3
expressions <- parse(file.path(legacy, "scripts/comparar_ventanas_propension_xgboost_com.R"), encoding = "UTF-8")
texts <- vapply(expressions, function(expression) paste(deparse(expression), collapse = " "), character(1))
eval(expressions[[grep("^rolling_previo <- function", texts)]], original)
start <- grep("^setorder\\(datos", texts)
end <- grep("^a0 <- fread", texts)
stopifnot(length(start) == 1L, length(end) == 1L)
for (index in seq.int(start, end - 1L)) {
  eval(expressions[[index]], original)
}
expected <- original$base[anchor, on = c("dia_objetivo", "barrio", "segmento"), nomatch = 0]
expected[, delta_q_7_60 := media_q_7 - media_q_60]
columns <- c("dia_objetivo", "barrio", "segmento", "n_clusters", "observado",
  "media_tiempo_levante", "rms_q_7", "rms_w_7", "delta_q_7_60")
actual <- copy(prepared$p3_base)
setorder(expected, dia_objetivo, barrio, segmento)
setorder(actual, dia_objetivo, barrio, segmento)
stopifnot(isTRUE(all.equal(expected[, ..columns], actual[, ..columns], tolerance = 1e-12)))
cat("R07_FEATURES_LEGACY_EQUIVALENT:", nrow(actual), "filas\n")

modified <- copy(features)
modified[dia >= as.IDate("2026-05-23"), tuvo_reclamo := 1L - tuvo_reclamo]
changed <- rf_build_aggregate(modified, geography, calendar, holidays)$p3_base
predictors <- c("barrio", "segmento", "media_tiempo_levante", "rms_q_7", "rms_w_7", "delta_q_7_60")
stopifnot(isTRUE(all.equal(prepared$p3_base[dia_objetivo == as.IDate("2026-05-24"), ..predictors],
  changed[dia_objetivo == as.IDate("2026-05-24"), ..predictors], tolerance = 1e-12)))
cat("R07_NO_LEAKAGE_D2_OK\n")
unknown_targets <- copy(features)
unknown_targets[dia == as.IDate("2026-05-24"), tuvo_reclamo := NA_integer_]
unknown_base <- rf_build_aggregate(unknown_targets, geography, calendar, holidays)$p3_base
stopifnot(all(is.na(unknown_base[dia_objetivo == as.IDate("2026-05-24"), observado])),
  isTRUE(all.equal(prepared$p3_base[dia_objetivo == as.IDate("2026-05-24"), ..predictors],
    unknown_base[dia_objetivo == as.IDate("2026-05-24"), ..predictors], tolerance = 1e-12)))
cat("R07_UNKNOWN_OBSERVED_REMAINS_NA\n")
bad <- copy(sample$base)
bad[, dia_objetivo := as.IDate("2025-12-31")]
stopifnot(inherits(try(rf_score_aggregate(bad, bundle), silent = TRUE), "try-error"))
new_segment <- copy(sample$base[1L])
new_segment[, segmento := "segmento_no_visto"]
stopifnot(is.finite(rf_predict_a0(new_segment, bundle$a0)))
new_segment[, barrio := "barrio_no_visto"]
stopifnot(inherits(try(rf_predict_a0(new_segment, bundle$a0), silent = TRUE), "try-error"))

# Prueba el puente de canonicos en un arbol que deliberadamente no contiene app.
legacy_fixture <- tempfile("r07_canonical_fixture_")
paths <- c(features = "data/processed/modelo_cluster_dia/features_cluster_dia",
  admin = "data/processed/cluster_territorial/cluster_admin_territorial",
  segments = "data/processed/cluster_territorial/cluster_segmento_censal")
for (relative in paths) {
  dir.create(file.path(legacy_fixture, relative), recursive = TRUE)
}
raw_features <- copy(features)
raw_features[, `:=`(version_cluster = bundle$version_cluster, cluster_existente_dia = TRUE)]
raw_geo <- copy(geography)
raw_geo[, version_cluster := bundle$version_cluster]
arrow::write_dataset(raw_features, file.path(legacy_fixture, paths[["features"]]), format = "parquet")
arrow::write_dataset(raw_geo[, .(version_cluster, cluster_id, nombre_barrio_ine = barrio)],
  file.path(legacy_fixture, paths[["admin"]]), format = "parquet")
arrow::write_dataset(raw_geo[, .(version_cluster, cluster_id, codseg_centroide = segmento)],
  file.path(legacy_fixture, paths[["segments"]]), format = "parquet")
holiday_directory <- file.path(legacy_fixture, "data/reference/feriados")
dir.create(holiday_directory, recursive = TRUE)
writeLines("diasDesc <- as.Date('2026-05-01')", file.path(holiday_directory, "feriados.R"))
canonical_path <- tempfile("r07_canonical_", fileext = ".rds")
prepared_path <- tempfile("r07_prepared_", fileext = ".rds")
output <- system2(file.path(R.home("bin"), "Rscript.exe"), c("--vanilla",
  shQuote(file.path(root, "herramientas_migracion/importar_insumos_agregado_r07.R")),
  shQuote(legacy_fixture), "2026-05-24", shQuote(canonical_path)), stdout = TRUE, stderr = TRUE)
if (!is.null(attr(output, "status"))) {
  stop(paste(output, collapse = "\n"))
}
output <- system2(file.path(R.home("bin"), "Rscript.exe"), c("--vanilla",
  shQuote(file.path(root, "scripts/preparar_agregado.R")), shQuote(canonical_path), shQuote(prepared_path)),
  stdout = TRUE, stderr = TRUE)
if (!is.null(attr(output, "status"))) {
  stop(paste(output, collapse = "\n"))
}
from_canonical <- readRDS(prepared_path)
stopifnot(nrow(from_canonical$p3_base) == nrow(prepared$p3_base),
  isTRUE(all.equal(from_canonical$p3_base[, ..columns], prepared$p3_base[, ..columns], tolerance = 1e-12)))
cat("R07_CANONICAL_WITHOUT_APP_OK\n")

input_path <- tempfile("r07_fixture_", fileext = ".rds")
output_path <- tempfile("r07_candidate_")
saveRDS(prepared, input_path)
output <- system2(file.path(R.home("bin"), "Rscript.exe"), c("--vanilla",
  shQuote(file.path(root, "scripts/entrenar_agregado.R")), shQuote(input_path), shQuote(output_path)),
  stdout = TRUE, stderr = TRUE)
if (!is.null(attr(output, "status"))) {
  stop(paste(output, collapse = "\n"))
}
result <- readRDS(file.path(output_path, "resultado.rds"))
stopifnot(all(result$oof$max_training_day < result$oof$first_target_day),
  result$status == "candidato_no_promovido", result$bundle$best_iteration >= 1L,
  nrow(result$metrics) == 3L, all(is.finite(result$metrics$rmse)))
cat("R07_TRAINING_FIXTURE_OK: folds=", nrow(result$oof), " best_iteration=",
  result$bundle$best_iteration, " seconds=", result$seconds, "\n", sep = "")
