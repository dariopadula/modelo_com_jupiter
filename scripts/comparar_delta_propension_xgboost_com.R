library(data.table)
library(xgboost)

set.seed(20260826)

path_base <- file.path(
  "outputs", "comparacion_ventanas_propension_xgboost_com",
  "base_segmento_dia_ventanas.csv"
)
path_modelo_w7 <- file.path(
  "outputs", "comparacion_ventanas_propension_xgboost_com",
  "modelo_X2_W7.rds"
)
path_pred_w7 <- file.path(
  "outputs", "comparacion_ventanas_propension_xgboost_com",
  "predicciones_diarias.csv"
)
path_out <- "outputs/comparacion_delta_propension_xgboost_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base <- fread(path_base)
base[, dia_objetivo := as.IDate(dia_objetivo)]
base[, `:=`(
  dia_semana = factor(dia_semana),
  delta_q_7_30 = media_q_7 - media_q_30,
  delta_q_7_60 = media_q_7 - media_q_60
)]

features_base <- c(
  "media_tiempo_levante", "media_periodo", "media_ratio", "media_h",
  "prop_exceso_positivo", "prop_exceso_mayor_1",
  "media_q_7", "rms_q_7", "media_w_7", "rms_w_7"
)

crear_matriz <- function(dt, adicional) {
  vars <- c(features_base, adicional)
  model.matrix(as.formula(paste(
    "~ dia_semana +", paste(vars, collapse = " + "), "- 1"
  )), data = dt)
}

idx_fit <- which(base$split_modelo == "entrenamiento" &
  base$dia_objetivo < as.IDate("2025-11-01"))
idx_es <- which(base$split_modelo == "entrenamiento" &
  base$dia_objetivo >= as.IDate("2025-11-01"))
idx_train <- which(base$split_modelo == "entrenamiento")

params <- list(
  objective = "binary:logistic", eval_metric = "logloss",
  eta = 0.03, max_depth = 3L, min_child_weight = 100,
  subsample = 0.80, colsample_bytree = 0.80,
  lambda = 10, alpha = 0, tree_method = "hist", nthread = 4L
)

ajustar <- function(nombre, adicional) {
  X <- crear_matriz(base, adicional)
  construir_dmat <- function(idx) {
    d <- xgb.DMatrix(
      X[idx, , drop = FALSE], label = base$prop_reclamo[idx],
      weight = base$n_clusters[idx]
    )
    setinfo(d, "base_margin", base$margen_a0[idx])
    d
  }
  dfit <- construir_dmat(idx_fit)
  des <- construir_dmat(idx_es)
  fit_es <- xgb.train(
    params = params, data = dfit, nrounds = 800L,
    watchlist = list(train = dfit, seleccion = des),
    early_stopping_rounds = 40L, verbose = 0
  )
  mejor_iter <- fit_es$best_iteration
  dtrain <- construir_dmat(idx_train)
  fit <- xgb.train(
    params = params, data = dtrain, nrounds = mejor_iter, verbose = 0
  )
  dnew <- xgb.DMatrix(X)
  setinfo(dnew, "base_margin", base$margen_a0)
  prob <- as.numeric(predict(fit, dnew))
  saveRDS(fit, file.path(path_out, paste0("modelo_", nombre, ".rds")))
  list(
    pred = base[, .(dia_objetivo, split_modelo, n_clusters, observado)][
      , `:=`(escenario = nombre, prob_predicha = prob)
    ],
    diag = data.table(
      escenario = nombre,
      variable_adicional = adicional,
      mejor_iteracion = mejor_iter,
      logloss_seleccion = fit_es$best_score
    ),
    importancia = as.data.table(xgb.importance(model = fit))[
      , escenario := nombre
    ]
  )
}

ajustes <- list(
  X2_W7_D30 = ajustar("X2_W7_D30", "delta_q_7_30"),
  X2_W7_D60 = ajustar("X2_W7_D60", "delta_q_7_60")
)

# Se reutiliza la prediccion W7 ya ajustada sobre exactamente la misma base.
pred_w7_dia <- fread(path_pred_w7)[escenario == "X2_W7"]
pred_w7_dia[, dia_objetivo := as.IDate(dia_objetivo)]

pred <- rbindlist(lapply(ajustes, `[[`, "pred"))
pred[, predicho_segmento := n_clusters * prob_predicha]
pred_dia <- pred[, .(
  observado = sum(observado), predicho = sum(predicho_segmento)
), by = .(escenario, split_modelo, dia_objetivo)]
pred_dia[, mes := format(dia_objetivo, "%Y-%m")]
pred_dia <- rbindlist(list(pred_w7_dia, pred_dia), use.names = TRUE)

metricas_fun <- function(dt, grupos) {
  dt[, {
    error <- predicho - observado
    .(
      dias = .N, media_observada = mean(observado),
      media_predicha = mean(predicho), sesgo = mean(error),
      mae = mean(abs(error)), rmse = sqrt(mean(error^2)),
      correlacion = cor(observado, predicho),
      razon_sd = sd(predicho) / sd(observado)
    )
  }, by = grupos]
}

metricas_periodo <- metricas_fun(
  pred_dia[split_modelo %in% c("validacion", "test")],
  c("escenario", "split_modelo")
)
metricas_combinadas <- metricas_fun(
  pred_dia[split_modelo %in% c("validacion", "test")], "escenario"
)[, split_modelo := "validacion + test"]
setcolorder(metricas_combinadas, names(metricas_periodo))
metricas_periodo <- rbindlist(list(metricas_periodo, metricas_combinadas))
metricas_mensuales <- metricas_fun(pred_dia, c("escenario", "mes"))

diagnosticos <- rbindlist(lapply(ajustes, `[[`, "diag"))
importancias <- rbindlist(lapply(ajustes, `[[`, "importancia"), fill = TRUE)

fwrite(diagnosticos, file.path(path_out, "diagnostico_modelos.csv"))
fwrite(importancias, file.path(path_out, "importancia_variables.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas_periodo, file.path(path_out, "metricas_periodo.csv"))
fwrite(metricas_mensuales, file.path(path_out, "metricas_mensuales.csv"))

print(diagnosticos)
print(metricas_periodo[split_modelo == "validacion"][order(rmse)])
print(metricas_periodo[split_modelo == "test"][order(rmse)])
print(metricas_periodo[split_modelo == "validacion + test"][order(rmse)])
print(importancias[Feature %in% c("delta_q_7_30", "delta_q_7_60")])
