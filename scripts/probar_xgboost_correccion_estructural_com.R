library(data.table)
library(mgcv)
library(xgboost)

set.seed(20260826)

path_a0 <- file.path(
  "outputs", "benchmark_modelo_segmento_barrio_com", "base_segmento_dia.csv"
)
path_x <- file.path(
  "outputs", "exploracion_carga_atraso_ponderada_propension_com",
  "indicadores_segmento_dia.csv"
)
path_out <- "outputs/prueba_xgboost_correccion_estructural_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base_a0 <- fread(path_a0)
base_a0[, dia_objetivo := as.IDate(dia_objetivo)]
base_a0[, barrio := factor(base_a0$barrio)]
base_a0[, segmento := factor(as.character(base_a0$segmento))]
base_a0[, dia_semana := factor(base_a0$dia_semana)]

base <- fread(path_x)
base[, dia_objetivo := as.IDate(dia_objetivo)]
variables_requeridas <- c(
  "media_tiempo_levante", "media_periodo", "media_ratio", "media_h",
  "prop_exceso_positivo", "prop_exceso_mayor_1", "media_q", "rms_q",
  "media_w", "rms_w"
)
base <- base[
  split_modelo %in% c("entrenamiento", "validacion", "test") &
    n_clusters > 0
]
filas_validas <- base[, Reduce(`&`, lapply(.SD, is.finite)),
  .SDcols = variables_requeridas]
base <- base[filas_validas]
base[, barrio := factor(base$barrio, levels = levels(base_a0$barrio))]
base[, segmento := factor(
  as.character(base$segmento), levels = levels(base_a0$segmento)
)]
base[, dia_semana := factor(
  base$dia_semana, levels = levels(base_a0$dia_semana)
)]
base[, prop_reclamo := observado / n_clusters]
base[, fila_id := .I]

formula_a0 <- prop_clusters_reclamo ~ dia_semana +
  s(barrio, bs = "re") + s(segmento, bs = "re")

predecir_a0 <- function(fit, newdata, train) {
  segmentos_train <- unique(as.character(train$segmento))
  barrios_train <- unique(as.character(train$barrio))
  segmento_nuevo <- !as.character(newdata$segmento) %in% segmentos_train
  barrio_nuevo <- !as.character(newdata$barrio) %in% barrios_train
  if (any(barrio_nuevo)) stop("Hay barrios nuevos fuera de entrenamiento A0")

  pred <- rep(NA_real_, nrow(newdata))
  if (any(!segmento_nuevo)) {
    pred[!segmento_nuevo] <- as.numeric(predict.gam(
      fit, newdata = newdata[!segmento_nuevo, , drop = FALSE], type = "response"
    ))
  }
  if (any(segmento_nuevo)) {
    nd <- newdata[segmento_nuevo, , drop = FALSE]
    nd$segmento <- factor(segmentos_train[[1L]], levels = levels(train$segmento))
    pred[segmento_nuevo] <- as.numeric(predict.gam(
      fit, newdata = nd, type = "response", exclude = "s(segmento)"
    ))
  }
  pred
}

# A0 OOF mensual para las filas que luego entrenan XGBoost.
base[, prob_a0 := NA_real_]
meses_oof <- sort(unique(format(
  base[split_modelo == "entrenamiento", dia_objetivo], "%Y-%m"
)))
diag_a0 <- list()
for (mes_obj in meses_oof) {
  inicio_mes <- as.IDate(paste0(mes_obj, "-01"))
  train_a0 <- base_a0[
    split_modelo == "entrenamiento" & dia_objetivo < inicio_mes
  ]
  objetivo <- base[split_modelo == "entrenamiento" &
    format(dia_objetivo, "%Y-%m") == mes_obj]
  if (!nrow(train_a0) || !nrow(objetivo)) next

  tiempo <- system.time({
    fit <- bam(
      formula_a0,
      data = train_a0,
      family = binomial(),
      weights = n_clusters,
      method = "fREML",
      discrete = TRUE,
      nthreads = 2L
    )
  })
  nd <- as.data.frame(objetivo[, .(barrio, segmento, dia_semana)])
  base[objetivo$fila_id, prob_a0 := predecir_a0(fit, nd, train_a0)]
  diag_a0[[mes_obj]] <- data.table(
    mes_objetivo = mes_obj,
    fecha_max_train = max(train_a0$dia_objetivo),
    filas_train = nrow(train_a0),
    filas_objetivo = nrow(objetivo),
    segundos = unname(tiempo[["elapsed"]])
  )
}

# A0 final entrenado con 2025 para validacion y test.
train_a0_final <- base_a0[split_modelo == "entrenamiento"]
fit_a0_final <- bam(
  formula_a0,
  data = train_a0_final,
  family = binomial(),
  weights = n_clusters,
  method = "fREML",
  discrete = TRUE,
  nthreads = 2L
)
idx_eval <- which(base$split_modelo %in% c("validacion", "test"))
nd_eval <- as.data.frame(base[idx_eval, .(barrio, segmento, dia_semana)])
base[idx_eval, prob_a0 := predecir_a0(fit_a0_final, nd_eval, train_a0_final)]
base[, prob_a0 := pmin(pmax(prob_a0, 1e-5), 1 - 1e-5)]
if (base[, any(!is.finite(prob_a0))]) stop("Hay probabilidades A0 faltantes")
base[, margen_a0 := qlogis(prob_a0)]
fwrite(base[, .(
  dia_objetivo, split_modelo, barrio, segmento, dia_semana,
  n_clusters, observado, prop_reclamo, prob_a0, margen_a0
)], file.path(path_out, "base_a0_oof_segmento_dia.csv"))

features_levante <- c(
  "media_tiempo_levante", "media_periodo", "media_ratio", "media_h",
  "prop_exceso_positivo", "prop_exceso_mayor_1"
)
features_propension <- c("media_q", "rms_q", "media_w", "rms_w")

crear_matriz <- function(dt, features) {
  f <- as.formula(paste(
    "~ dia_semana +", paste(features, collapse = " + "), "- 1"
  ))
  model.matrix(f, data = dt)
}

features_x2 <- c(features_levante, features_propension)
X_full <- crear_matriz(base, features_x2)
columnas_x1 <- grep(
  paste(c("^dia_semana", features_levante), collapse = "|"),
  colnames(X_full), value = TRUE
)
columnas_x2 <- colnames(X_full)

idx_train_fit <- which(
  base$split_modelo == "entrenamiento" & base$dia_objetivo < as.IDate("2025-11-01")
)
idx_train_es <- which(
  base$split_modelo == "entrenamiento" & base$dia_objetivo >= as.IDate("2025-11-01")
)
idx_train_total <- which(base$split_modelo == "entrenamiento")

params <- list(
  objective = "binary:logistic",
  eval_metric = "logloss",
  eta = 0.03,
  max_depth = 3L,
  min_child_weight = 100,
  subsample = 0.80,
  colsample_bytree = 0.80,
  lambda = 10,
  alpha = 0,
  tree_method = "hist",
  nthread = 4L
)

ajustar_xgb <- function(nombre, columnas, usar_margen) {
  dfit <- xgb.DMatrix(
    data = X_full[idx_train_fit, columnas, drop = FALSE],
    label = base$prop_reclamo[idx_train_fit],
    weight = base$n_clusters[idx_train_fit]
  )
  des <- xgb.DMatrix(
    data = X_full[idx_train_es, columnas, drop = FALSE],
    label = base$prop_reclamo[idx_train_es],
    weight = base$n_clusters[idx_train_es]
  )
  if (usar_margen) {
    setinfo(dfit, "base_margin", base$margen_a0[idx_train_fit])
    setinfo(des, "base_margin", base$margen_a0[idx_train_es])
  }
  fit_es <- xgb.train(
    params = params,
    data = dfit,
    nrounds = 800L,
    watchlist = list(train = dfit, seleccion = des),
    early_stopping_rounds = 40L,
    verbose = 0
  )
  mejor_iter <- fit_es$best_iteration

  dtotal <- xgb.DMatrix(
    data = X_full[idx_train_total, columnas, drop = FALSE],
    label = base$prop_reclamo[idx_train_total],
    weight = base$n_clusters[idx_train_total]
  )
  if (usar_margen) {
    setinfo(dtotal, "base_margin", base$margen_a0[idx_train_total])
  }
  fit <- xgb.train(
    params = params, data = dtotal, nrounds = mejor_iter, verbose = 0
  )
  saveRDS(fit, file.path(path_out, paste0("modelo_", nombre, ".rds")))
  list(
    fit = fit,
    columnas = columnas,
    usar_margen = usar_margen,
    mejor_iter = mejor_iter,
    logloss_seleccion = fit_es$best_score
  )
}

ajustes <- list(
  X0_desde_cero = ajustar_xgb("X0_desde_cero", columnas_x2, FALSE),
  X1_a0_mas_levante = ajustar_xgb("X1_a0_mas_levante", columnas_x1, TRUE),
  X2_a0_levante_propension = ajustar_xgb(
    "X2_a0_levante_propension", columnas_x2, TRUE
  )
)

predicciones <- list(
  A0_estructura = base[, .(
    dia_objetivo, split_modelo, observado, n_clusters,
    escenario = "A0_estructura", prob_predicha = prob_a0
  )]
)
for (nombre in names(ajustes)) {
  aj <- ajustes[[nombre]]
  dnew <- xgb.DMatrix(data = X_full[, aj$columnas, drop = FALSE])
  if (aj$usar_margen) setinfo(dnew, "base_margin", base$margen_a0)
  prob <- as.numeric(predict(aj$fit, dnew))
  predicciones[[nombre]] <- base[, .(
    dia_objetivo, split_modelo, observado, n_clusters
  )][, `:=`(escenario = nombre, prob_predicha = prob)]
}

pred <- rbindlist(predicciones, use.names = TRUE)
pred[, predicho_segmento := n_clusters * prob_predicha]
pred_dia <- pred[, .(
  observado = sum(observado),
  predicho = sum(predicho_segmento)
), by = .(escenario, split_modelo, dia_objetivo)]
pred_dia[, mes := format(dia_objetivo, "%Y-%m")]

metricas_fun <- function(dt, grupos) {
  dt[, {
    error <- predicho - observado
    .(
      dias = .N,
      media_observada = mean(observado),
      media_predicha = mean(predicho),
      sesgo = mean(error),
      mae = mean(abs(error)),
      rmse = sqrt(mean(error^2)),
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

diag_xgb <- rbindlist(lapply(names(ajustes), function(nombre) {
  aj <- ajustes[[nombre]]
  data.table(
    escenario = nombre,
    usa_base_margin_a0 = aj$usar_margen,
    n_features = length(aj$columnas),
    mejor_iteracion = aj$mejor_iter,
    logloss_seleccion = aj$logloss_seleccion
  )
}))
importancias <- rbindlist(lapply(names(ajustes), function(nombre) {
  imp <- as.data.table(xgb.importance(model = ajustes[[nombre]]$fit))
  imp[, escenario := nombre]
  imp
}), fill = TRUE)

saveRDS(fit_a0_final, file.path(path_out, "modelo_A0_final.rds"))
fwrite(rbindlist(diag_a0), file.path(path_out, "diagnostico_a0_oof.csv"))
fwrite(diag_xgb, file.path(path_out, "diagnostico_xgboost.csv"))
fwrite(importancias, file.path(path_out, "importancia_variables.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas_periodo, file.path(path_out, "metricas_periodo.csv"))
fwrite(metricas_mensuales, file.path(path_out, "metricas_mensuales.csv"))

print(rbindlist(diag_a0))
print(diag_xgb)
print(metricas_periodo[split_modelo == "validacion"][order(rmse)])
print(metricas_periodo[split_modelo == "test"][order(rmse)])
print(metricas_periodo[split_modelo == "validacion + test"][order(rmse)])
print(importancias[, head(.SD, 10L), by = escenario])
