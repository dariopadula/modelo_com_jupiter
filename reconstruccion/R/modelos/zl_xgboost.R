# Rehidrata y puntua el escenario ZL efectivo del bundle congelado.
# Entradas: features cluster/dia y bundle R06; salida: score, ranking y top flags.
rf_score_zl <- function(features, model, universe_n = NULL) {
  features <- data.table::as.data.table(features)
  required <- c("cluster_id", "dia", "version_cluster", model$features_numericas)
  missing <- setdiff(required, names(features))
  if (length(missing)) {
    stop("Faltan columnas para scoring ZL: ", paste(missing, collapse = ", "))
  }
  if (!identical(model$feature_set_zl, "operativo_segmento") || length(model$features_categoricas)) {
    stop("El bundle ZL no corresponde al escenario efectivo operativo_segmento")
  }
  if (!"random_dia_estratificado_mes" %in% names(model)) {
    stop("Falta el escenario ZL congelado random_dia_estratificado_mes")
  }
  if (anyNA(features$version_cluster) || any(features$version_cluster != model$version_cluster)) {
    stop("Version espacial incompatible con el bundle ZL")
  }
  if (anyDuplicated(features[, .(cluster_id, dia)])) {
    stop("Features ZL duplicadas por cluster y dia")
  }
  if (anyNA(features$dia) || anyNA(features$cluster_id) || data.table::uniqueN(features$dia) != 1L) {
    stop("El adaptador ZL requiere un unico dia con claves completas")
  }

  scenario <- model$random_dia_estratificado_mes
  prepared <- rf_prepare_zl_matrix(features, model$features_numericas,
    model$features_categoricas, prep = scenario$prep)
  booster <- xgboost::xgb.Booster.complete(scenario$fit)
  probabilities <- as.numeric(stats::predict(booster, xgboost::xgb.DMatrix(prepared$x)))
  scored <- data.table::data.table(
    cluster_id = as.character(features$cluster_id),
    dia_objetivo = as.Date(features$dia),
    modelo_id = "zl_problema",
    version_modelo = "xgboost_operativo_segmento_random_dia_estratificado_mes",
    version_cluster = as.character(features$version_cluster),
    pred_prob = probabilities
  )
  scored <- scored[order(-pred_prob, cluster_id)]
  scored[, ranking_dia := seq_len(.N)]
  universe <- if (is.null(universe_n)) nrow(scored) else as.integer(universe_n)
  if (length(universe) != 1L || is.na(universe) || universe < nrow(scored)) {
    stop("Universo ZL invalido o menor que las filas puntuadas")
  }
  scored[, percentil_riesgo := ranking_dia / universe]
  for (percentage in c(1L, 5L, 10L, 20L)) {
    scored[, (paste0("top_", percentage)) := percentil_riesgo <= percentage / 100]
  }
  scored[]
}
