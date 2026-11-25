# Prediccion compuesta A0 + P3. No consulta fuentes, entrena ni publica.

# Aplica A0 conservando factores y el fallback original para segmentos nuevos.
# Un barrio nuevo se rechaza; un segmento nuevo omite solo su efecto aleatorio.
rf_predict_a0 <- function(base, fit) {
  data <- as.data.frame(base[, .(barrio, segmento, dia_semana)])
  barrios <- unique(as.character(fit$model$barrio))
  segmentos <- unique(as.character(fit$model$segmento))
  unknown <- !as.character(data$segmento) %in% segmentos
  if (any(!as.character(data$barrio) %in% barrios)) {
    stop("Hay barrios nuevos fuera del entrenamiento A0")
  }
  data$barrio <- factor(as.character(data$barrio), levels = levels(fit$model$barrio))
  data$segmento <- factor(as.character(data$segmento), levels = levels(fit$model$segmento))
  data$dia_semana <- factor(as.character(data$dia_semana), levels = fit$xlevels$dia_semana)
  if (anyNA(data$dia_semana)) {
    stop("Calendario incompatible con los niveles del bundle A0")
  }
  probability <- rep(NA_real_, nrow(data))
  if (any(!unknown)) {
    probability[!unknown] <- as.numeric(mgcv::predict.gam(fit, data[!unknown, , drop = FALSE], type = "response"))
  }
  if (any(unknown)) {
    data$segmento[unknown] <- segmentos[[1L]]
    probability[unknown] <- as.numeric(mgcv::predict.gam(fit, data[unknown, , drop = FALSE],
      type = "response", exclude = "s(segmento)"))
  }
  pmin(pmax(probability, 1e-5), 1 - 1e-5)
}

# Aplica P3 con margen A0 explicito y construye series cuya exposicion suma por barrio.
rf_correct_aggregate <- function(base, margin, booster) {
  columns <- c("media_tiempo_levante", "rms_q_7", "rms_w_7", "delta_q_7_60", "es_feriado")
  required <- c("dia_objetivo", "barrio", "segmento", "n_clusters", "observado", "split_modelo", columns)
  if (length(setdiff(required, names(base))) || !nrow(base) ||
      anyDuplicated(base[, .(dia_objetivo, barrio, segmento)]) ||
      anyNA(base[, .(dia_objetivo, barrio, segmento)]) ||
      any(!is.finite(base$n_clusters) | base$n_clusters <= 0) ||
      any(!is.finite(margin)) || length(margin) != nrow(base)) {
    stop("Base, exposicion o margen A0 incompatible con P3")
  }
  matrix <- as.matrix(base[, ..columns])
  if (any(!is.finite(matrix))) {
    stop("P3 requiere cinco variables finitas en el orden congelado")
  }
  fit <- xgboost::xgb.Booster.complete(booster)
  if (!identical(fit$feature_names, columns)) {
    stop("El modelo P3 no corresponde al esquema de cinco variables congelado")
  }
  input <- xgboost::xgb.DMatrix(matrix)
  xgboost::setinfo(input, "base_margin", margin)
  segments <- data.table::copy(base)
  segments[, `:=`(prob_predicha = as.numeric(predict(fit, input)), escenario = "P3_compacto")]
  segments[, predicho_segmento := n_clusters * prob_predicha]
  neighborhood <- segments[, .(observado = sum(observado), predicho = sum(predicho_segmento),
    n_clusters = sum(n_clusters)), by = .(escenario, split_modelo, barrio, dia_objetivo)]
  daily <- neighborhood[, .(observado = sum(observado), predicho = sum(predicho),
    n_clusters = sum(n_clusters)), by = .(escenario, split_modelo, dia_objetivo)]
  list(segmento = segments, barrio = neighborhood, montevideo = daily)
}

# Inferencia fuera del entrenamiento. Los historicos de train requieren margenes OOF,
# que se calculan por el entrenador, nunca reutilizando A0 ajustado en esas filas.
rf_score_aggregate <- function(base, bundle) {
  base <- data.table::as.data.table(base)
  if (!all(c("a0", "p3", "a0_trained_until", "version_cluster") %in% names(bundle)) ||
      length(bundle$a0_trained_until) != 1L || anyNA(bundle$a0_trained_until) ||
      !nrow(base) || anyNA(base$dia_objetivo)) {
    stop("Faltan bundle, fecha de entrenamiento o fechas objetivo validas")
  }
  if (!"version_cluster" %in% names(base) || anyNA(base$version_cluster) ||
      any(base$version_cluster != bundle$version_cluster)) {
    stop("Version espacial incompatible con el compuesto A0/P3")
  }
  if (any(data.table::as.IDate(base$dia_objetivo) <= data.table::as.IDate(bundle$a0_trained_until))) {
    stop("Para fechas de entrenamiento se requieren margenes OOF; no usar A0 final")
  }
  margin <- stats::qlogis(rf_predict_a0(base, bundle$a0))
  rf_correct_aggregate(base, margin, bundle$p3)
}
