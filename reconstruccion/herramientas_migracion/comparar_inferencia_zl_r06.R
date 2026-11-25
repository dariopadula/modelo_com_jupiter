# Compara el publicador original y el adaptador R06 con un mismo bundle e insumos.
# Solo evalua definiciones de funciones del legado: no ejecuta su script principal.
# Uso: Rscript comparar_inferencia_zl_r06.R <raiz_original>

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L) {
  stop("Se requiere la raiz original como argumento explicito")
}
script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
reconstruction_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/")
legacy_root <- normalizePath(arguments[[1L]], winslash = "/", mustWork = TRUE)
library_version <- paste0(R.version$major, ".", sub("\\..*$", "", R.version$minor))
user_library <- Sys.getenv("RF_R_LIBRARY", unset = "")
if (!nzchar(user_library) && nzchar(Sys.getenv("USERPROFILE"))) {
  user_library <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "R", "win-library", library_version)
}
if (dir.exists(user_library)) {
  .libPaths(c(user_library, .libPaths()))
}
library(data.table)
source(file.path(reconstruction_root, "R/features/zl_receta.R"))
source(file.path(reconstruction_root, "R/modelos/zl_xgboost.R"))

# Extrae funciones por nombre mediante el parser de R, sin efectos del publicador.
load_functions <- function(source_path, requested, environment) {
  expressions <- parse(source_path)
  loaded <- character()
  for (expression in expressions) {
    if (is.call(expression) && identical(expression[[1L]], as.name("<-")) &&
        is.symbol(expression[[2L]]) && is.call(expression[[3L]]) &&
        identical(expression[[3L]][[1L]], as.name("function"))) {
      name <- as.character(expression[[2L]])
      if (name %in% requested) {
        eval(expression, envir = environment)
        loaded <- c(loaded, name)
      }
    }
  }
  if (!setequal(loaded, requested)) {
    stop("No se encontraron todas las funciones originales solicitadas")
  }
}

original <- new.env(parent = globalenv())
publisher_path <- file.path(legacy_root, "scripts/construir_app_modelos_largo_historico.R")
load_functions(publisher_path, c("normalizar_nivel", "nombre_seguro",
  "preparar_matriz_xgb_app", "agregar_features_zl_app"), original)
load_functions(file.path(legacy_root, "funciones/scoring_operativo_utils.R"),
  "agregar_ranking_operativo", original)

model <- readRDS(file.path(reconstruction_root, "runtime/r06_zl/modelo_zl.rds"))
sample <- readRDS(file.path(reconstruction_root, "runtime/r06_zl/muestra_zl.rds"))$data
segment_fields <- c("porc_nbi_segmento", "porc_asentamiento_nbi_segmento",
  "porc_vivienda_inadecuada_segmento", "densidad_pob_km2", "cluster_multisegmento",
  "pct_posiciones_segmento_principal")
derived_fields <- grep("^exceso_", model$features_numericas, value = TRUE)
calendar_fields <- c("dia_semana", "fin_de_semana", "es_feriado", "vispera_feriado", "dia_habil")
base_fields <- setdiff(names(sample), c(segment_fields, derived_fields, calendar_fields, "pred_prob"))
base <- copy(sample[, ..base_fields])
segment_columns <- c("version_cluster", "cluster_id", segment_fields)
segments <- unique(sample[, ..segment_columns])
holiday_environment <- new.env(parent = baseenv())
sys.source(file.path(legacy_root, "data/reference/feriados/feriados.R"), holiday_environment)
holidays <- as.IDate(holiday_environment$diasDesc)

features_original <- original$agregar_features_zl_app(copy(base), copy(segments), holidays)
features_new <- rf_prepare_zl_features(copy(base), copy(segments), holidays, model$features_numericas)
setorder(features_original, version_cluster, cluster_id, dia)
setorder(features_new, version_cluster, cluster_id, dia)
numeric_features <- model$features_numericas
scenario <- model$random_dia_estratificado_mes
matrix_original <- original$preparar_matriz_xgb_app(features_original, numeric_features,
  model$features_categoricas, scenario$prep)
matrix_new <- rf_prepare_zl_matrix(features_new, numeric_features,
  model$features_categoricas, scenario$prep)$x
if (!isTRUE(all.equal(matrix_original, matrix_new, tolerance = 1e-12))) {
  stop("Las matrices del publicador y de R06 difieren con los mismos insumos")
}

booster <- xgboost::xgb.Booster.complete(scenario$fit)
pred_original <- data.table(cluster_id = features_original$cluster_id,
  dia_objetivo = as.Date(features_original$dia),
  pred_prob = as.numeric(predict(booster, matrix_original)))
pred_original <- original$agregar_ranking_operativo(pred_original)
pred_new <- rf_score_zl(features_new, model)
stopifnot(identical(pred_original$cluster_id, pred_new$cluster_id),
  identical(pred_original$dia_objetivo, pred_new$dia_objetivo))
max_difference <- max(abs(pred_original$pred_prob - pred_new$pred_prob))
stopifnot(max_difference <= 1e-6)
for (column in c("ranking_dia", "percentil_riesgo", "top_1", "top_5", "top_10", "top_20")) {
  stopifnot(identical(pred_original[[column]], pred_new[[column]]))
}
cat("R06_ZL_SAME_INPUTS_OK: filas=", nrow(pred_new), " features=", length(numeric_features),
  " max_abs_diff=", format(max_difference, scientific = TRUE), " ranking_y_top=iguales\n", sep = "")
