# Entrena exclusivamente las familias COM reducido D-2 y ZL operativo_segmento.
# Recibe tablas propias ya preparadas; no lee fuentes ni activa modelos publicados.

# Resume discriminacion y calibracion por split sin dependencias de evaluacion extra.
rf_training_metrics <- function(predictions) {
  predictions[, {
    # El producto de clases puede superar el limite entero de R en COM completo.
    positives <- as.double(sum(target))
    negatives <- as.double(.N) - positives
    auc <- if (positives && negatives) {
      (sum(rank(pred_prob)[target == 1L]) - positives * (positives + 1) / 2) /
        (positives * negatives)
    } else {
      NA_real_
    }
    probability <- pmin(pmax(pred_prob, 1e-15), 1 - 1e-15)
    list(n = .N, positivos = positives, prevalencia = mean(target), auc = auc,
      logloss = -mean(target * log(probability) + (1 - target) * log(1 - probability)),
      brier = mean((target - pred_prob)^2))
  }, by = split]
}

# Ajusta un modelo seleccionado y devuelve bundle, predicciones y metricas.
# reference fija variables/splits COM o parametros ZL. seed queda registrado.
rf_train_selected <- function(features, family, reference, seed = 20260703L) {
  data <- data.table::copy(data.table::as.data.table(features))
  if (!family %in% c("com", "zl")) {
    stop("Familia no soportada: ", family)
  }
  keys <- c("version_cluster", "cluster_id", "dia", "anio_mes")
  if (length(setdiff(keys, names(data)))) {
    stop("Faltan claves del entrenamiento")
  }
  data[, dia := data.table::as.IDate(dia)]
  if (anyNA(data[, ..keys]) || anyDuplicated(data[, .(version_cluster, cluster_id, dia)]) ||
      any(as.character(data$version_cluster) != as.character(reference$version_cluster))) {
    stop("Claves duplicadas, incompletas o version espacial incompatible")
  }

  if (family == "com") {
    if (reference$rezago_reclamos_dias != 2L) {
      stop("La referencia COM debe ser D-2")
    }
    data <- aplicar_rezago_historia_reclamos(data, reference$rezago_reclamos_dias)
    data <- agregar_features_logistico_reducido(data[dia >= data.table::as.IDate(reference$fecha_min_modelo)])
    data[, split := data.table::fcase(
      anio_mes %in% reference$meses_train, "train",
      anio_mes %in% reference$meses_validacion, "validacion",
      anio_mes %in% reference$meses_test, "test", default = NA_character_
    )]
    data[, target := as.integer(tuvo_reclamo)]
    model_features <- reference$features_modelo
  } else {
    if (!identical(reference$feature_set_zl, "operativo_segmento") ||
        length(reference$features_categoricas)) {
      stop("Solo se entrena ZL operativo_segmento numerico")
    }
    parameters <- reference$parametros
    months <- as.integer(strsplit(parameters$meses_modelo[[1L]], ",", fixed = TRUE)[[1L]])
    data <- data[anio_mes %in% months]
    # Preserva el orden de primera aparicion del dia, igual que el script original.
    # Se guardan las claves/splits para que el resultado no dependa de releer Arrow.
    days <- unique(data[, .(anio_mes, dia)])
    set.seed(seed)
    days[, random_u := runif(.N)]
    days[, fraction := data.table::frank(random_u, ties.method = "random") / .N, by = anio_mes]
    days[, split := data.table::fcase(fraction <= 0.70, "train",
      fraction <= 0.85, "validacion", default = "test")]
    data <- days[, .(anio_mes, dia, split)][data, on = c("anio_mes", "dia")]
    data[, target := as.integer(target_problema_observado)]
    model_features <- reference$features_numericas
  }

  data <- data[!is.na(split)]
  if (anyNA(data$target) || !all(data$target %in% c(0L, 1L)) ||
      !setequal(unique(data$split), c("train", "validacion", "test"))) {
    stop("Se requieren targets binarios completos y tres splits no vacios")
  }
  train <- data[split == "train"]
  if (data.table::uniqueN(train$target) != 2L) {
    stop("El entrenamiento debe contener ambas clases")
  }
  set.seed(seed)
  if (family == "com") {
    prepared <- preparar_matriz(train, model_features,
      no_agregar_na_features = reference$no_agregar_na_features)
    fit <- stats::glm.fit(cbind(intercept = 1, prepared$x), train$target,
      family = stats::binomial())
    if (!isTRUE(fit$converged)) {
      stop("El entrenamiento COM no convergio; no se produce un candidato")
    }
    coefficients <- fit$coefficients
    coefficients[is.na(coefficients)] <- 0
    model <- c(list(features_modelo = model_features, prep = prepared$prep,
      coeficientes_prediccion = coefficients), reference[setdiff(names(reference), "features_modelo")])
    matrix_all <- preparar_matriz(data, model_features, prep = prepared$prep)$x
    data[, pred_prob := as.numeric(stats::plogis(cbind(intercept = 1, matrix_all) %*% coefficients))]
  } else {
    prepared <- rf_prepare_zl_matrix(train, model_features)
    parameter_names <- c("max_depth", "eta", "subsample", "colsample_bytree", "min_child_weight")
    xgb_parameters <- as.list(parameters[1L, ..parameter_names])
    xgb_parameters <- c(list(objective = "binary:logistic", eval_metric = "logloss", nthread = 4L),
      xgb_parameters)
    fit <- xgboost::xgb.train(params = xgb_parameters,
      data = xgboost::xgb.DMatrix(prepared$x, label = train$target),
      nrounds = parameters$nrounds[[1L]], verbose = 0)
    model <- reference
    model$random_dia_estratificado_mes <- list(fit = fit, prep = prepared$prep)
    model$fit <- fit
    model$prep <- prepared$prep
    matrix_all <- rf_prepare_zl_matrix(data, model_features, prep = prepared$prep)$x
    data[, pred_prob := as.numeric(predict(fit, xgboost::xgb.DMatrix(matrix_all)))]
    model$parametros <- data.table::copy(parameters)
    model$parametros[, `:=`(filas_train = sum(data$split == "train"),
      filas_validacion = sum(data$split == "validacion"), filas_test = sum(data$split == "test"))]
  }

  predictions <- data[, .(version_cluster, cluster_id, dia, anio_mes, split, target, pred_prob)]
  list(model = model, predictions = predictions, metrics = rf_training_metrics(predictions),
    family = family, seed = seed, status = "candidato_no_promovido")
}
