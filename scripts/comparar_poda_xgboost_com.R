library(data.table)
library(xgboost)

set.seed(20260827)

path_base <- file.path(
  "outputs", "comparacion_ventanas_propension_xgboost_com",
  "base_segmento_dia_ventanas.csv"
)
path_feriados <- file.path("data", "reference", "feriados", "feriados.R")
path_out <- "outputs/comparacion_poda_xgboost_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

env_feriados <- new.env(parent = baseenv())
sys.source(path_feriados, envir = env_feriados)
feriados <- sort(unique(as.IDate(env_feriados$diasDesc)))

base <- fread(path_base)
base[, dia_objetivo := as.IDate(dia_objetivo)]
base[, `:=`(
  dia_semana = factor(dia_semana),
  delta_q_7_60 = media_q_7 - media_q_60,
  es_feriado = as.integer(dia_objetivo %in% feriados)
)]

especificaciones <- list(
  P0_completo = list(
    dia_semana = TRUE,
    variables = c(
      "media_tiempo_levante", "media_periodo", "media_ratio", "media_h",
      "prop_exceso_positivo", "prop_exceso_mayor_1",
      "media_q_7", "rms_q_7", "media_w_7", "rms_w_7",
      "delta_q_7_60", "es_feriado"
    )
  ),
  P1_sin_redundantes = list(
    dia_semana = FALSE,
    variables = c(
      "media_tiempo_levante", "media_periodo", "media_h",
      "rms_q_7", "rms_w_7", "delta_q_7_60", "es_feriado"
    )
  ),
  P2_compacto_con_h = list(
    dia_semana = FALSE,
    variables = c(
      "media_tiempo_levante", "media_h", "rms_q_7", "rms_w_7",
      "delta_q_7_60", "es_feriado"
    )
  ),
  P3_compacto = list(
    dia_semana = FALSE,
    variables = c(
      "media_tiempo_levante", "rms_q_7", "rms_w_7",
      "delta_q_7_60", "es_feriado"
    )
  ),
  P3_compacto_calendario = list(
    dia_semana = TRUE,
    variables = c(
      "media_tiempo_levante", "rms_q_7", "rms_w_7",
      "delta_q_7_60", "es_feriado"
    )
  ),
  P4_minimo = list(
    dia_semana = FALSE,
    variables = c(
      "media_tiempo_levante", "rms_w_7", "delta_q_7_60", "es_feriado"
    )
  )
)

crear_matriz <- function(dt, spec) {
  terminos <- c(
    if (isTRUE(spec$dia_semana)) "dia_semana" else character(),
    spec$variables
  )
  model.matrix(as.formula(paste(
    "~", paste(terminos, collapse = " + "), "- 1"
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

ajustar <- function(nombre, spec) {
  X <- crear_matriz(base, spec)
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
    pred = base[, .(
      dia_objetivo, split_modelo, barrio, segmento, n_clusters, observado
    )][, `:=`(escenario = nombre, prob_predicha = prob)],
    diag = data.table(
      escenario = nombre,
      n_variables_conceptuales = length(spec$variables) + spec$dia_semana,
      incluye_dia_semana = spec$dia_semana,
      variables = paste(spec$variables, collapse = "+"),
      mejor_iteracion = mejor_iter,
      logloss_seleccion = fit_es$best_score
    ),
    importancia = as.data.table(xgb.importance(model = fit))[
      , escenario := nombre
    ]
  )
}

ajustes <- Map(ajustar, names(especificaciones), especificaciones)
pred <- rbindlist(lapply(ajustes, `[[`, "pred"))
pred[, predicho_segmento := n_clusters * prob_predicha]
pred_dia <- pred[, .(
  observado = sum(observado),
  predicho = sum(predicho_segmento)
), by = .(escenario, split_modelo, dia_objetivo)]
pred_dia[, mes := format(dia_objetivo, "%Y-%m")]

pred_barrio_dia <- pred[, .(
  observado = sum(observado),
  predicho = sum(predicho_segmento),
  n_clusters = sum(n_clusters)
), by = .(escenario, split_modelo, barrio, dia_objetivo)]

pred_a0_barrio <- base[, .(
  escenario = "A0_estructura",
  observado = sum(observado),
  predicho = sum(n_clusters * prob_a0),
  n_clusters = sum(n_clusters)
), by = .(split_modelo, barrio, dia_objetivo)]
pred_barrio_dia <- rbindlist(
  list(pred_barrio_dia, pred_a0_barrio), use.names = TRUE
)

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

metricas_barrio <- pred_barrio_dia[
  split_modelo %in% c("validacion", "test"),
  {
    error <- predicho - observado
    media_obs <- mean(observado)
    sd_obs <- sd(observado)
    .(
      dias = .N,
      media_observada = media_obs,
      media_predicha = mean(predicho),
      sesgo = mean(error),
      mae = mean(abs(error)),
      rmse = sqrt(mean(error^2)),
      rmse_rel_media = if (media_obs > 0) sqrt(mean(error^2)) / media_obs else NA_real_,
      correlacion = if (sd_obs > 0 && sd(predicho) > 0) {
        cor(observado, predicho)
      } else {
        NA_real_
      },
      razon_sd = if (sd_obs > 0) sd(predicho) / sd_obs else NA_real_
    )
  },
  by = .(escenario, barrio)
]

diagnosticos <- rbindlist(lapply(ajustes, `[[`, "diag"))
importancias <- rbindlist(lapply(ajustes, `[[`, "importancia"), fill = TRUE)
fwrite(diagnosticos, file.path(path_out, "diagnostico_modelos.csv"))
fwrite(importancias, file.path(path_out, "importancia_variables.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas_periodo, file.path(path_out, "metricas_periodo.csv"))
fwrite(metricas_mensuales, file.path(path_out, "metricas_mensuales.csv"))
fwrite(pred_barrio_dia, file.path(path_out, "predicciones_barrio_dia.csv"))
fwrite(metricas_barrio, file.path(path_out, "metricas_barrio.csv"))

print(diagnosticos)
print(metricas_periodo[split_modelo == "validacion"][order(rmse)])
print(metricas_periodo[split_modelo == "test"][order(rmse)])
print(metricas_periodo[split_modelo == "validacion + test"][order(rmse)])
