library(arrow)
library(data.table)
library(dplyr)
library(mgcv)
library(xgboost)

source("funciones/splits_temporales.R")

set.seed(20260916)

path_base <- "data/processed/features_compartidas/segmento_dia"
path_out <- "data/processed/modelos/reevaluacion_2026/agregados_inferencia"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base <- as.data.table(as.data.frame(
  arrow::open_dataset(path_base, format = "parquet") |>
    dplyr::filter(dia <= as.Date("2026-06-30")) |>
    dplyr::collect()
))
base[, dia := as.IDate(dia)]
base <- asignar_split_congelado(base)
base <- base[split %in% c("entrenamiento", "validacion")]
base[, `:=`(
  prop_reclamo = observado / n_clusters,
  dia_semana = factor(dia_semana),
  es_feriado = factor(as.integer(es_feriado)),
  barrio = factor(barrio),
  segmento = factor(segmento)
)]

variables_continuas <- c(
  "log_densidad_pob", "porc_nbi_segmento", "media_h",
  "media_q_30", "delta_q_7_30"
)
train <- base[split == "entrenamiento"]
valid <- base[split == "validacion"]
preparacion <- rbindlist(lapply(variables_continuas, function(variable) {
  x <- train[[variable]]
  mediana <- median(x[is.finite(x)], na.rm = TRUE)
  x[!is.finite(x)] <- mediana
  data.table(
    variable = variable, mediana_train = mediana,
    media_train = mean(x), sd_train = sd(x)
  )
}))
for (variable in variables_continuas) {
  p <- preparacion[match(variable, preparacion[["variable"]])]
  x <- base[[variable]]
  x[!is.finite(x)] <- p$mediana_train
  base[, paste0("z_", variable) := (x - p$media_train) / p$sd_train]
}
train <- droplevels(base[split == "entrenamiento"])
valid <- base[split == "validacion"]
valid[, `:=`(
  dia_semana = factor(dia_semana, levels = levels(train$dia_semana)),
  es_feriado = factor(es_feriado, levels = levels(train$es_feriado)),
  barrio = factor(barrio, levels = levels(train$barrio)),
  segmento = factor(segmento, levels = levels(train$segmento))
)]

formula_a0 <- prop_reclamo ~ dia_semana +
  s(barrio, bs = "re") + s(segmento, bs = "re")
formula_inferencial <- prop_reclamo ~
  dia_semana + es_feriado + sin_anual + cos_anual +
  z_log_densidad_pob + z_porc_nbi_segmento +
  z_media_h + z_media_q_30 + z_delta_q_7_30 +
  z_media_h:z_delta_q_7_30 + z_media_h:dia_semana +
  s(barrio, bs = "re") + s(segmento, bs = "re")

ajustar_bam <- function(formula) {
  bam(
    formula, data = train, family = binomial(), weights = n_clusters,
    method = "fREML", discrete = TRUE, nthreads = 2L
  )
}
fit_a0 <- ajustar_bam(formula_a0)
fit_inferencial <- ajustar_bam(formula_inferencial)

prob_a0_train <- as.numeric(predict(fit_a0, newdata = train, type = "response"))
prob_a0_valid <- as.numeric(predict(fit_a0, newdata = valid, type = "response"))
prob_inf_valid <- as.numeric(predict(
  fit_inferencial, newdata = valid, type = "response"
))

features_xgb <- c(
  "media_tiempo_levante", "rms_q_7", "rms_w_7",
  "delta_q_7_30", "es_feriado"
)
crear_matriz_xgb <- function(dt) {
  model.matrix(
    ~ media_tiempo_levante + rms_q_7 + rms_w_7 +
      delta_q_7_30 + es_feriado - 1,
    data = dt
  )
}
x_train <- crear_matriz_xgb(train)
x_valid <- crear_matriz_xgb(valid)
dtrain <- xgb.DMatrix(
  x_train, label = train$prop_reclamo, weight = train$n_clusters
)
dvalid <- xgb.DMatrix(x_valid)
setinfo(
  dtrain, "base_margin",
  qlogis(pmin(pmax(prob_a0_train, 1e-8), 1 - 1e-8))
)
setinfo(
  dvalid, "base_margin",
  qlogis(pmin(pmax(prob_a0_valid, 1e-8), 1 - 1e-8))
)
params_xgb <- list(
  objective = "binary:logistic", eval_metric = "logloss",
  eta = 0.03, max_depth = 3L, min_child_weight = 100,
  subsample = 0.80, colsample_bytree = 0.80,
  lambda = 10, alpha = 0, tree_method = "hist", nthread = 4L
)
fit_xgb <- xgb.train(
  params = params_xgb, data = dtrain, nrounds = 57L, verbose = 0
)
prob_xgb_valid <- as.numeric(predict(fit_xgb, dvalid))

pred_segmento <- rbindlist(list(
  valid[, .(
    version_cluster, dia, barrio, segmento, n_clusters, observado,
    split, candidato = "pronostico_a0", prob_predicha = prob_a0_valid
  )],
  valid[, .(
    version_cluster, dia, barrio, segmento, n_clusters, observado,
    split, candidato = "pronostico_a0_xgb_compacto_q30",
    prob_predicha = prob_xgb_valid
  )],
  valid[, .(
    version_cluster, dia, barrio, segmento, n_clusters, observado,
    split, candidato = "inferencial_q30_ciclo",
    prob_predicha = prob_inf_valid
  )]
))
pred_segmento[, predicho := n_clusters * prob_predicha]
pred_dia <- pred_segmento[, .(
  observado = sum(observado), predicho = sum(predicho)
), by = .(candidato, split, dia)]

saveRDS(list(
  fit = fit_a0, formula = formula_a0,
  version_split = "reevaluacion_2026_v1"
), file.path(path_out, "pronostico_a0.rds"))
saveRDS(list(
  fit_a0 = fit_a0, fit_xgb = fit_xgb, features = features_xgb,
  params = params_xgb, nrounds = 57L,
  version_split = "reevaluacion_2026_v1"
), file.path(path_out, "pronostico_a0_xgb_compacto_q30.rds"))
saveRDS(list(
  fit = fit_inferencial, formula = formula_inferencial,
  preparacion = preparacion, version_split = "reevaluacion_2026_v1",
  bootstrap = FALSE
), file.path(path_out, "inferencial_q30_ciclo.rds"))
arrow::write_parquet(
  pred_segmento, file.path(path_out, "predicciones_segmento_validacion.parquet"),
  compression = "zstd"
)
fwrite(pred_dia, file.path(path_out, "predicciones_diarias_validacion.csv"))
fwrite(preparacion, file.path(path_out, "preparacion_variables.csv"))

inventario <- data.table(
  candidato = c(
    "pronostico_a0", "pronostico_a0_xgb_compacto_q30",
    "inferencial_q30_ciclo"
  ),
  familia = c("pronostico_agregado", "pronostico_agregado", "inferencia"),
  algoritmo = c("bam_binomial", "bam_mas_xgboost", "bam_binomial"),
  filas_train = nrow(train), filas_validacion = nrow(valid),
  version_split = "reevaluacion_2026_v1",
  usa_test = FALSE, bootstrap = FALSE
)
fwrite(inventario, file.path(path_out, "inventario.csv"))
print(inventario)
