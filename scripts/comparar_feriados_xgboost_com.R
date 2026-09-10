library(data.table)
library(xgboost)
library(arrow)

set.seed(20260827)

path_base <- file.path(
  "outputs", "comparacion_ventanas_propension_xgboost_com",
  "base_segmento_dia_ventanas.csv"
)
path_pred_actual <- file.path(
  "outputs", "comparacion_delta_propension_xgboost_com",
  "predicciones_diarias.csv"
)
path_modelo_actual <- file.path(
  "outputs", "comparacion_delta_propension_xgboost_com",
  "modelo_X2_W7_D60.rds"
)
path_feriados <- file.path("data", "reference", "feriados", "feriados.R")
path_pred_cluster <- paste0(
  "app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia/",
  "modelo_id=com_reclamo"
)
path_out <- "outputs/comparacion_feriados_xgboost_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

cargar_feriados <- function(path) {
  if (!file.exists(path)) stop("No existe el calendario de feriados: ", path)
  env <- new.env(parent = baseenv())
  sys.source(path, envir = env)
  if (!exists("diasDesc", envir = env, inherits = FALSE)) {
    stop("El calendario no define diasDesc: ", path)
  }
  sort(unique(as.IDate(get("diasDesc", envir = env, inherits = FALSE))))
}

feriados <- cargar_feriados(path_feriados)
post_feriados <- feriados + 1L
post_feriados <- post_feriados[!post_feriados %in% feriados]

base <- fread(path_base)
base[, dia_objetivo := as.IDate(dia_objetivo)]

# Dinamica explicita del barrio, agregada desde las propensiones de cluster
# resumidas en cada segmento y ponderada por la exposicion del segmento.
propension_barrio <- base[, .(
  q_barrio_7 = weighted.mean(media_q_7, n_clusters),
  q_barrio_60 = weighted.mean(media_q_60, n_clusters)
), by = .(dia_objetivo, barrio)]
propension_barrio[, delta_q_barrio_7_60 := q_barrio_7 - q_barrio_60]
base[propension_barrio, on = c("dia_objetivo", "barrio"), `:=`(
  q_barrio_7 = i.q_barrio_7,
  q_barrio_60 = i.q_barrio_60,
  delta_q_barrio_7_60 = i.delta_q_barrio_7_60
)]
if (base[, any(!is.finite(q_barrio_7) | !is.finite(delta_q_barrio_7_60))]) {
  stop("Hay filas sin propension barrial")
}

# Cambio reciente del volumen global observado, disponible solo hasta D-2.
pred_cluster <- as.data.table(as.data.frame(
  open_dataset(path_pred_cluster) |>
    dplyr::select(dia_objetivo, tuvo_reclamo_observado) |>
    dplyr::collect()
))
pred_cluster[, dia_objetivo := as.IDate(dia_objetivo)]
global_dia <- pred_cluster[!is.na(tuvo_reclamo_observado), .(
  clusters_con_reclamo = sum(tuvo_reclamo_observado == 1L)
), by = dia_objetivo]
setorder(global_dia, dia_objetivo)
if (global_dia[, any(diff(dia_objetivo) != 1L)]) {
  stop("La serie global de reclamos tiene huecos diarios")
}
global_dia[, `:=`(
  media_com_7_d2 = shift(frollmean(clusters_con_reclamo, 7L), 2L),
  media_com_60_d2 = shift(frollmean(clusters_con_reclamo, 60L), 2L)
)]
global_dia[, `:=`(
  delta_com_7_60 = media_com_7_d2 - media_com_60_d2,
  ratio_com_7_60 = media_com_7_d2 / media_com_60_d2
)]
base[global_dia, on = "dia_objetivo", `:=`(
  media_com_7_d2 = i.media_com_7_d2,
  media_com_60_d2 = i.media_com_60_d2,
  delta_com_7_60 = i.delta_com_7_60,
  ratio_com_7_60 = i.ratio_com_7_60
)]
if (base[, any(!is.finite(delta_com_7_60) | !is.finite(ratio_com_7_60))]) {
  stop("Hay filas sin historia global COM de 7 y 60 dias")
}

if (base[, any(!is.finite(media_top20_h))]) {
  stop("Hay filas sin top20_h en la muestra del modelo")
}
cobertura_top20_h <- base[, .(
  filas = .N,
  filas_top20_h_validas = sum(is.finite(media_top20_h)),
  pct_top20_h_valido = 100 * mean(is.finite(media_top20_h))
)]
base[, `:=`(
  dia_semana = factor(dia_semana),
  delta_q_7_60 = media_q_7 - media_q_60,
  es_feriado = as.integer(dia_objetivo %in% feriados),
  post_feriado = as.integer(dia_objetivo %in% post_feriados)
)]

features_base <- c(
  "media_tiempo_levante", "media_periodo", "media_ratio", "media_h",
  "prop_exceso_positivo", "prop_exceso_mayor_1",
  "media_q_7", "rms_q_7", "media_w_7", "rms_w_7",
  "delta_q_7_60"
)

crear_matriz <- function(dt, adicionales = character()) {
  vars <- c(features_base, adicionales)
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

ajustar <- function(nombre, adicionales) {
  X <- crear_matriz(base, adicionales)
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
      dia_objetivo, split_modelo, barrio, segmento, n_clusters, observado,
      es_feriado, post_feriado
    )][, `:=`(escenario = nombre, prob_predicha = prob)],
    diag = data.table(
      escenario = nombre,
      variables_adicionales = paste(adicionales, collapse = "+"),
      mejor_iteracion = mejor_iter,
      logloss_seleccion = fit_es$best_score
    ),
    importancia = as.data.table(xgb.importance(model = fit))[
      , escenario := nombre
    ]
  )
}

ajustes <- list(
  X2_W7_D60_F = ajustar("X2_W7_D60_F", "es_feriado"),
  X2_W7_D60_FP = ajustar(
    "X2_W7_D60_FP", c("es_feriado", "post_feriado")
  ),
  X2_W7_D60_F_H20 = ajustar(
    "X2_W7_D60_F_H20", c("es_feriado", "media_top20_h")
  ),
  X2_W7_D60_F_DCOM = ajustar(
    "X2_W7_D60_F_DCOM", c("es_feriado", "delta_com_7_60")
  ),
  X2_W7_D60_F_RCOM = ajustar(
    "X2_W7_D60_F_RCOM", c("es_feriado", "ratio_com_7_60")
  ),
  X2_W7_D60_F_BQ7 = ajustar(
    "X2_W7_D60_F_BQ7", c("es_feriado", "q_barrio_7")
  ),
  X2_W7_D60_F_BQ7D = ajustar(
    "X2_W7_D60_F_BQ7D",
    c("es_feriado", "q_barrio_7", "delta_q_barrio_7_60")
  )
)

pred_actual_dia <- fread(path_pred_actual)[escenario == "X2_W7_D60"]
pred_actual_dia[, dia_objetivo := as.IDate(dia_objetivo)]
pred_actual_dia[, `:=`(
  es_feriado = as.integer(dia_objetivo %in% feriados),
  post_feriado = as.integer(dia_objetivo %in% post_feriados)
)]

# Predicciones segmento/dia necesarias para la evaluacion territorial.
predecir_modelo_actual <- function() {
  fit <- readRDS(path_modelo_actual)
  X <- crear_matriz(base)
  dnew <- xgb.DMatrix(X)
  setinfo(dnew, "base_margin", base$margen_a0)
  as.numeric(predict(fit, dnew))
}
prob_modelo_actual <- predecir_modelo_actual()
pred_segmento_comparables <- rbindlist(list(
  base[, .(
    dia_objetivo, split_modelo, barrio, segmento, n_clusters, observado,
    escenario = "A0_estructura", prob_predicha = prob_a0
  )],
  base[, .(
    dia_objetivo, split_modelo, barrio, segmento, n_clusters, observado,
    escenario = "X2_W7_D60", prob_predicha = prob_modelo_actual
  )],
  ajustes$X2_W7_D60_F$pred[, .(
    dia_objetivo, split_modelo, barrio, segmento, n_clusters, observado,
    escenario, prob_predicha
  )]
))
pred_segmento_comparables[, predicho_segmento := n_clusters * prob_predicha]
pred_barrio_dia <- pred_segmento_comparables[, .(
  observado = sum(observado),
  predicho = sum(predicho_segmento),
  n_clusters = sum(n_clusters)
), by = .(escenario, split_modelo, barrio, dia_objetivo)]

pred <- rbindlist(lapply(ajustes, `[[`, "pred"))
pred[, predicho_segmento := n_clusters * prob_predicha]
pred_dia <- pred[, .(
  observado = sum(observado),
  predicho = sum(predicho_segmento),
  es_feriado = unique(es_feriado),
  post_feriado = unique(post_feriado)
), by = .(escenario, split_modelo, dia_objetivo)]
pred_dia[, mes := format(dia_objetivo, "%Y-%m")]
pred_dia <- rbindlist(list(pred_actual_dia, pred_dia), use.names = TRUE)

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
metricas_tipo_dia <- metricas_fun(
  pred_dia[split_modelo %in% c("validacion", "test")][
    , tipo_dia := fcase(
      es_feriado == 1L, "feriado",
      post_feriado == 1L, "post_feriado",
      default = "dia_regular"
    )
  ],
  c("escenario", "tipo_dia")
)
umbrales_extremos <- pred_dia[
  escenario == "X2_W7_D60" &
    split_modelo %in% c("validacion", "test"),
  .(
    p10 = as.numeric(quantile(observado, 0.10, type = 8)),
    p90 = as.numeric(quantile(observado, 0.90, type = 8))
  )
]
metricas_extremos <- metricas_fun(
  pred_dia[split_modelo %in% c("validacion", "test")][
    , tipo_extremo := fcase(
      observado <= umbrales_extremos$p10, "pico_bajo",
      observado >= umbrales_extremos$p90, "pico_alto",
      default = "nivel_intermedio"
    )
  ],
  c("escenario", "tipo_extremo")
)

metricas_barrio_fun <- function(dt, grupos) {
  dt[, {
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
      mae_rel_media = if (media_obs > 0) mean(abs(error)) / media_obs else NA_real_,
      rmse_rel_media = if (media_obs > 0) sqrt(mean(error^2)) / media_obs else NA_real_,
      correlacion = if (sd_obs > 0 && sd(predicho) > 0) {
        cor(observado, predicho)
      } else {
        NA_real_
      },
      razon_sd = if (sd_obs > 0) sd(predicho) / sd_obs else NA_real_
    )
  }, by = grupos]
}

metricas_barrio_periodo <- metricas_barrio_fun(
  pred_barrio_dia[split_modelo %in% c("validacion", "test")],
  c("escenario", "split_modelo", "barrio")
)
metricas_barrio_combinadas <- metricas_barrio_fun(
  pred_barrio_dia[split_modelo %in% c("validacion", "test")],
  c("escenario", "barrio")
)[, split_modelo := "validacion + test"]
setcolorder(metricas_barrio_combinadas, names(metricas_barrio_periodo))
metricas_barrio <- rbindlist(list(
  metricas_barrio_periodo, metricas_barrio_combinadas
))

comparacion_barrio <- dcast(
  metricas_barrio[split_modelo == "validacion + test"],
  barrio ~ escenario,
  value.var = c("rmse", "mae", "sesgo", "correlacion", "rmse_rel_media")
)
comparacion_barrio[, `:=`(
  delta_rmse_x2_vs_a0 = rmse_X2_W7_D60 - rmse_A0_estructura,
  delta_rmse_feriado_vs_x2 = rmse_X2_W7_D60_F - rmse_X2_W7_D60,
  delta_rmse_feriado_vs_a0 = rmse_X2_W7_D60_F - rmse_A0_estructura
)]

diagnosticos <- rbindlist(lapply(ajustes, `[[`, "diag"))
importancias <- rbindlist(lapply(ajustes, `[[`, "importancia"), fill = TRUE)
calendario <- data.table(
  dia_objetivo = sort(unique(base$dia_objetivo)),
  es_feriado = as.integer(sort(unique(base$dia_objetivo)) %in% feriados),
  post_feriado = as.integer(sort(unique(base$dia_objetivo)) %in% post_feriados)
)

fwrite(diagnosticos, file.path(path_out, "diagnostico_modelos.csv"))
fwrite(importancias, file.path(path_out, "importancia_variables.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas_periodo, file.path(path_out, "metricas_periodo.csv"))
fwrite(metricas_mensuales, file.path(path_out, "metricas_mensuales.csv"))
fwrite(metricas_tipo_dia, file.path(path_out, "metricas_tipo_dia.csv"))
fwrite(metricas_extremos, file.path(path_out, "metricas_extremos.csv"))
fwrite(cobertura_top20_h, file.path(path_out, "cobertura_top20_h.csv"))
fwrite(global_dia, file.path(path_out, "historia_global_com.csv"))
fwrite(propension_barrio, file.path(path_out, "propension_barrio_dia.csv"))
fwrite(pred_barrio_dia, file.path(path_out, "predicciones_barrio_dia.csv"))
fwrite(metricas_barrio, file.path(path_out, "metricas_barrio.csv"))
fwrite(comparacion_barrio, file.path(path_out, "comparacion_barrio.csv"))
fwrite(calendario, file.path(path_out, "calendario_modelo.csv"))

print(diagnosticos)
print(metricas_periodo[split_modelo == "validacion"][order(rmse)])
print(metricas_periodo[split_modelo == "test"][order(rmse)])
print(metricas_periodo[split_modelo == "validacion + test"][order(rmse)])
print(metricas_tipo_dia[tipo_dia != "dia_regular"])
print(metricas_extremos[tipo_extremo != "nivel_intermedio"])
print(cobertura_top20_h)
print(comparacion_barrio[, .(
  barrios = .N,
  mejora_x2_vs_a0 = sum(delta_rmse_x2_vs_a0 < 0),
  mejora_feriado_vs_x2 = sum(delta_rmse_feriado_vs_x2 < 0),
  mejora_feriado_vs_a0 = sum(delta_rmse_feriado_vs_a0 < 0)
)])
print(importancias[Feature %in% c(
  "es_feriado", "post_feriado", "media_top20_h"
  , "delta_com_7_60", "ratio_com_7_60", "q_barrio_7",
  "delta_q_barrio_7_60"
)])
