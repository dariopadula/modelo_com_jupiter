# Entrena solo A0 + P3_compacto: OOF mensual, seleccion de iteraciones y refit.
# Las corridas completas son separadas de la operacion y no promueven modelos.

# Ajusta la estructura binomial A0 sobre filas anteriores identificadas por el llamador.
rf_fit_a0 <- function(training) {
  if (!nrow(training) || any(!is.finite(training$prop_clusters_reclamo)) ||
      any(training$prop_clusters_reclamo < 0 | training$prop_clusters_reclamo > 1) ||
      any(!is.finite(training$n_clusters) | training$n_clusters <= 0)) {
    stop("El entrenamiento A0 requiere observados completos y filas no vacias")
  }
  data <- data.table::copy(training)
  for (column in c("barrio", "segmento", "dia_semana")) {
    data[, (column) := factor(as.character(get(column)))]
  }
  formula <- stats::as.formula("prop_clusters_reclamo ~ dia_semana + s(barrio, bs='re') + s(segmento, bs='re')",
    env = asNamespace("mgcv"))
  fit <- mgcv::bam(formula, data = data, family = stats::binomial(), weights = n_clusters,
    method = "fREML", discrete = TRUE, nthreads = 2L)
  if (identical(fit$converged, FALSE)) {
    stop("El ajuste A0 no convergio")
  }
  fit
}

# Recibe a0_base y p3_base preparados desde canonicos; conserva OOF solo en train.
# Devuelve bundle candidato, predicciones, metricas y auditoria de fechas por fold.
rf_train_aggregate <- function(package) {
  a0_base <- data.table::copy(package$a0_base)
  base <- data.table::copy(package$p3_base)
  a0_base[, dia_objetivo := data.table::as.IDate(dia_objetivo)]
  base[, dia_objetivo := data.table::as.IDate(dia_objetivo)]
  if (anyNA(base$observado) || !setequal(unique(base$split_modelo), c("entrenamiento", "validacion", "test"))) {
    stop("El entrenamiento compuesto requiere observados y los tres splits completos")
  }
  if (anyDuplicated(base[, .(dia_objetivo, barrio, segmento)]) ||
      any(!is.finite(base$n_clusters) | base$n_clusters <= 0) ||
      any(base$observado < 0 | base$observado > base$n_clusters)) {
    stop("Claves o conteos P3 invalidos")
  }
  base[, margin := NA_real_]
  months <- sort(unique(format(base[split_modelo == "entrenamiento", dia_objetivo], "%Y-%m")))
  audit <- list()
  set.seed(20260826L)
  for (month in months) {
    first_day <- data.table::as.IDate(paste0(month, "-01"))
    training <- a0_base[split_modelo == "entrenamiento" & dia_objetivo < first_day]
    indices <- which(base$split_modelo == "entrenamiento" & format(base$dia_objetivo, "%Y-%m") == month)
    fit <- rf_fit_a0(training)
    base[indices, margin := stats::qlogis(rf_predict_a0(base[indices], fit))]
    audit[[month]] <- data.table::data.table(month = month, max_training_day = max(training$dia_objetivo),
      first_target_day = min(base$dia_objetivo[indices]), training_rows = nrow(training), target_rows = length(indices))
  }
  final_training <- a0_base[split_modelo == "entrenamiento"]
  final_a0 <- rf_fit_a0(final_training)
  evaluation <- which(base$split_modelo != "entrenamiento")
  if (any(base$dia_objetivo[evaluation] <= max(final_training$dia_objetivo))) {
    stop("Validacion/test A0 se superponen temporalmente con train")
  }
  base[evaluation, margin := stats::qlogis(rf_predict_a0(base[evaluation], final_a0))]
  if (any(!is.finite(base$margin))) {
    stop("No se completaron todos los margenes A0 OOF/final")
  }

  columns <- c("media_tiempo_levante", "rms_q_7", "rms_w_7", "delta_q_7_60", "es_feriado")
  matrix <- as.matrix(base[, ..columns])
  if (any(!is.finite(matrix))) {
    stop("Features P3 no finitas")
  }
  fit_indices <- which(base$split_modelo == "entrenamiento" & base$dia_objetivo < data.table::as.IDate("2025-11-01"))
  selection_indices <- which(base$split_modelo == "entrenamiento" & base$dia_objetivo >= data.table::as.IDate("2025-11-01"))
  all_training <- which(base$split_modelo == "entrenamiento")
  if (!length(fit_indices) || !length(selection_indices)) {
    stop("Se requieren train anterior a noviembre 2025 y seleccion noviembre/diciembre")
  }
  make_input <- function(indices) {
    input <- xgboost::xgb.DMatrix(matrix[indices, , drop = FALSE], label = base$observado[indices] / base$n_clusters[indices],
      weight = base$n_clusters[indices])
    xgboost::setinfo(input, "base_margin", base$margin[indices])
    input
  }
  parameters <- list(objective = "binary:logistic", eval_metric = "logloss", eta = 0.03,
    max_depth = 3L, min_child_weight = 100, subsample = 0.80, colsample_bytree = 0.80,
    lambda = 10, alpha = 0, tree_method = "hist", nthread = 4L)
  set.seed(20260827L)
  fit_input <- make_input(fit_indices)
  selection <- xgboost::xgb.train(parameters, fit_input, nrounds = 800L,
    watchlist = list(train = fit_input, seleccion = make_input(selection_indices)),
    early_stopping_rounds = 40L, verbose = 0)
  final_p3 <- xgboost::xgb.train(parameters, make_input(all_training),
    nrounds = selection$best_iteration, verbose = 0)
  bundle <- list(a0 = final_a0, p3 = final_p3, a0_trained_until = max(final_training$dia_objetivo),
    version_cluster = package$version_cluster, scenario = "P3_compacto",
    p3_features = columns, best_iteration = selection$best_iteration, parameters = parameters,
    seeds = c(a0 = 20260826L, p3 = 20260827L), status = "candidato_no_promovido")
  prediction <- rf_correct_aggregate(base, base$margin, final_p3)
  metrics <- prediction$montevideo[, .(dias = .N, mae = mean(abs(predicho - observado)),
    rmse = sqrt(mean((predicho - observado)^2)), sesgo = mean(predicho - observado)), by = split_modelo]
  list(bundle = bundle, predictions = prediction, metrics = metrics, oof = data.table::rbindlist(audit),
    margins = base[, .(dia_objetivo, barrio, segmento, split_modelo, margin)],
    status = "candidato_no_promovido")
}
