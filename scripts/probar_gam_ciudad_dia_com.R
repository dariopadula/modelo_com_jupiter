library(data.table)
library(mgcv)

path_base <- file.path(
  "outputs", "comparacion_ventanas_propension_xgboost_com",
  "base_segmento_dia_ventanas.csv"
)
path_pred_xgb <- file.path(
  "outputs", "comparacion_poda_xgboost_com", "predicciones_diarias.csv"
)
path_feriados <- file.path("data", "reference", "feriados", "feriados.R")

env_feriados <- new.env(parent = baseenv())
sys.source(path_feriados, envir = env_feriados)
feriados <- as.IDate(env_feriados$diasDesc)

base_segmento <- fread(path_base)
base_segmento[, dia_objetivo := as.IDate(dia_objetivo)]

base_dia <- base_segmento[, .(
  n_clusters = sum(n_clusters),
  observado = sum(observado),
  pred_a0 = sum(n_clusters * prob_a0),
  media_tiempo_levante = weighted.mean(media_tiempo_levante, n_clusters),
  media_h = weighted.mean(media_h, n_clusters),
  prop_exceso_positivo = weighted.mean(prop_exceso_positivo, n_clusters),
  rms_q_7 = sqrt(weighted.mean(rms_q_7^2, n_clusters)),
  rms_w_7 = sqrt(weighted.mean(rms_w_7^2, n_clusters)),
  delta_q_7_60 = weighted.mean(media_q_7 - media_q_60, n_clusters)
), by = .(dia_objetivo, split_modelo, dia_semana)]

base_dia[, `:=`(
  dia_semana = factor(dia_semana),
  es_feriado = factor(as.integer(dia_objetivo %in% feriados)),
  tiempo = as.numeric(dia_objetivo - min(dia_objetivo)),
  prop_reclamo = observado / n_clusters
)]

train <- base_dia[split_modelo == "entrenamiento"]

fit_estructural_ciudad <- gam(
  prop_reclamo ~ dia_semana,
  family = binomial(),
  weights = n_clusters,
  method = "REML",
  data = train
)

fit_lineal_ciudad <- gam(
  prop_reclamo ~ dia_semana + es_feriado + tiempo +
    media_tiempo_levante + prop_exceso_positivo +
    rms_q_7 + rms_w_7 + delta_q_7_60,
  family = binomial(),
  weights = n_clusters,
  method = "REML",
  data = train
)

fit_gam_ciudad <- gam(
  prop_reclamo ~ dia_semana + es_feriado +
    s(tiempo, k = 8, bs = "cr") +
    s(media_tiempo_levante, k = 5, bs = "cr") +
    s(prop_exceso_positivo, k = 5, bs = "cr") +
    s(rms_q_7, k = 5, bs = "cr") +
    s(rms_w_7, k = 5, bs = "cr") +
    s(delta_q_7_60, k = 5, bs = "cr"),
  family = binomial(),
  weights = n_clusters,
  method = "REML",
  select = TRUE,
  data = train
)

fit_gam_operativo <- gam(
  prop_reclamo ~ dia_semana + es_feriado +
    s(media_tiempo_levante, k = 5, bs = "cr") +
    s(prop_exceso_positivo, k = 5, bs = "cr") +
    s(rms_q_7, k = 5, bs = "cr") +
    s(rms_w_7, k = 5, bs = "cr") +
    s(delta_q_7_60, k = 5, bs = "cr"),
  family = binomial(),
  weights = n_clusters,
  method = "REML",
  select = TRUE,
  data = train
)

fit_gam_tiempo_lineal <- gam(
  prop_reclamo ~ dia_semana + es_feriado + tiempo +
    s(media_tiempo_levante, k = 5, bs = "cr") +
    s(prop_exceso_positivo, k = 5, bs = "cr") +
    s(rms_q_7, k = 5, bs = "cr") +
    s(rms_w_7, k = 5, bs = "cr") +
    s(delta_q_7_60, k = 5, bs = "cr"),
  family = binomial(),
  weights = n_clusters,
  method = "REML",
  select = TRUE,
  data = train
)

base_dia[, pred_estructural_ciudad := n_clusters * predict(
  fit_estructural_ciudad, newdata = base_dia, type = "response"
)]
base_dia[, pred_lineal_ciudad := n_clusters * predict(
  fit_lineal_ciudad, newdata = base_dia, type = "response"
)]
base_dia[, pred_gam_ciudad := n_clusters * predict(
  fit_gam_ciudad, newdata = base_dia, type = "response"
)]
base_dia[, pred_gam_operativo := n_clusters * predict(
  fit_gam_operativo, newdata = base_dia, type = "response"
)]
base_dia[, pred_gam_tiempo_lineal := n_clusters * predict(
  fit_gam_tiempo_lineal, newdata = base_dia, type = "response"
)]

pred_xgb <- fread(path_pred_xgb)[
  escenario == "P3_compacto",
  .(dia_objetivo = as.IDate(dia_objetivo), pred_xgb = predicho)
]
base_dia[pred_xgb, on = "dia_objetivo", pred_xgb := i.pred_xgb]

pred_larga <- melt(
  base_dia,
  id.vars = c("dia_objetivo", "split_modelo", "observado"),
  measure.vars = c(
    "pred_a0", "pred_estructural_ciudad", "pred_lineal_ciudad",
    "pred_gam_ciudad", "pred_gam_operativo", "pred_gam_tiempo_lineal",
    "pred_xgb"
  ),
  variable.name = "modelo",
  value.name = "predicho"
)

metricas <- pred_larga[
  split_modelo %in% c("validacion", "test"),
  {
    error <- predicho - observado
    sse <- sum(error^2)
    sst <- sum((observado - mean(observado))^2)
    .(
      dias = .N,
      sesgo = mean(error),
      mae = mean(abs(error)),
      rmse = sqrt(mean(error^2)),
      correlacion = cor(observado, predicho),
      r2 = 1 - sse / sst,
      razon_sd = sd(predicho) / sd(observado)
    )
  },
  by = .(modelo, split_modelo)
]

metricas_combinadas <- pred_larga[
  split_modelo %in% c("validacion", "test"),
  {
    error <- predicho - observado
    sse <- sum(error^2)
    sst <- sum((observado - mean(observado))^2)
    .(
      split_modelo = "validacion + test",
      dias = .N,
      sesgo = mean(error),
      mae = mean(abs(error)),
      rmse = sqrt(mean(error^2)),
      correlacion = cor(observado, predicho),
      r2 = 1 - sse / sst,
      razon_sd = sd(predicho) / sd(observado)
    )
  },
  by = modelo
]

metricas <- rbindlist(list(metricas, metricas_combinadas), use.names = TRUE)
setorder(metricas, split_modelo, rmse)

cat("Dias por split:\n")
print(base_dia[, .N, by = split_modelo])
cat("\nMetricas:\n")
print(metricas)
cat("\nEDF del GAM ciudad/dia:\n")
print(summary(fit_gam_ciudad)$s.table[, c("edf", "Ref.df", "p-value"), drop = FALSE])
