library(data.table)
library(mgcv)

path_base <- file.path(
  "outputs", "experimento_modelos_agregados_m0_m4_com",
  "base_territorio_dia_con_ratio.csv"
)
path_out <- file.path("outputs", "exploracion_residuos_levante_barrio_com")
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base <- fread(path_base)
base <- base[nivel_territorial == "barrio"]
base[, dia_objetivo := as.IDate(dia_objetivo)]
base[, `:=`(
  territorio = factor(territorio),
  dia_semana = factor(dia_semana),
  mes_num = month(dia_objetivo),
  sin_anual = sin(2 * pi * month(dia_objetivo) / 12),
  cos_anual = cos(2 * pi * month(dia_objetivo) / 12),
  mes_id = format(dia_objetivo, "%Y-%m")
)]

# Deliberadamente no incluye tiempo de levante, periodo ni ratios.
formula_base <- prop_clusters_reclamo ~ dia_semana + sin_anual + cos_anual +
  z_score_medio + z_score_sd + z_score_p90 +
  z_contenedores_activos_medio + z_pct_inferidos_medio +
  z_reclamos_lag1_medio + z_reclamos_7d_medio + z_reclamos_30d_medio +
  s(territorio, bs = "re")

ajustar_y_predecir <- function(train, evaluacion, etiqueta) {
  fit <- bam(
    formula_base,
    data = train,
    family = binomial(),
    weights = n_clusters,
    method = "fREML",
    discrete = TRUE,
    nthreads = 2L
  )
  p <- as.numeric(predict.gam(
    fit,
    newdata = as.data.frame(evaluacion[, setdiff(names(evaluacion), "dia_objetivo"), with = FALSE]),
    type = "response"
  ))
  out <- copy(evaluacion)
  out[, `:=`(
    prob_base = p,
    esperado_base = n_clusters * p,
    residuo_clusters = clusters_con_reclamo - n_clusters * p,
    residuo_pearson = (clusters_con_reclamo - n_clusters * p) /
      sqrt(pmax(n_clusters * p * (1 - p), 1e-8)),
    origen_residuo = etiqueta
  )]
  list(fit = fit, pred = out)
}

# Residuos OOF dentro de train: seis meses iniciales como minimo y ventana expansiva.
meses_train <- sort(unique(base[split_modelo == "entrenamiento", mes_id]))
meses_oof <- meses_train[seq.int(7L, length(meses_train))]
pred_oof <- list()
diag_folds <- list()

for (mes_eval in meses_oof) {
  train_fold <- base[split_modelo == "entrenamiento" & mes_id < mes_eval]
  eval_fold <- base[split_modelo == "entrenamiento" & mes_id == mes_eval]
  res <- ajustar_y_predecir(train_fold, eval_fold, "oof_train")
  pred_oof[[mes_eval]] <- res$pred
  diag_folds[[mes_eval]] <- data.table(
    mes_evaluado = mes_eval,
    primer_mes_train = min(train_fold$mes_id),
    ultimo_mes_train = max(train_fold$mes_id),
    dias_train = uniqueN(train_fold$dia_objetivo),
    dias_evaluacion = uniqueN(eval_fold$dia_objetivo),
    AIC_train = AIC(res$fit),
    convergencia = if (isTRUE(res$fit$converged)) "OK" else "REVISAR"
  )
}

# Comprobacion externa: modelo congelado con todo 2025 para validacion y test.
train_completo <- base[split_modelo == "entrenamiento"]
externo <- base[split_modelo %in% c("validacion", "test")]
res_externo <- ajustar_y_predecir(train_completo, externo, "externo_2026")
pred <- rbindlist(c(pred_oof, list(externo = res_externo$pred)), fill = TRUE)

variables_levante <- c(
  "tiempo_levante_medio",
  "tiempo_levante_p90",
  "pct_clusters_tiempo_3omas",
  "carga_exceso_media",
  "ratio_medio_territorio",
  "ratio_p90_territorio",
  "pct_ratio_1_5_2",
  "pct_ratio_mayor_2"
)

# Centrado dentro de barrio usando solo 2025; representa desvio frente a lo habitual.
referencias <- base[
  split_modelo == "entrenamiento",
  lapply(.SD, function(x) mean(x, na.rm = TRUE)),
  by = territorio,
  .SDcols = variables_levante
]
setnames(referencias, variables_levante, paste0(variables_levante, "_habitual"))
pred <- merge(pred, referencias, by = "territorio", all.x = TRUE, sort = FALSE)
for (v in variables_levante) {
  pred[, (paste0(v, "_desv")) := get(v) - get(paste0(v, "_habitual"))]
}

estandarizacion <- rbindlist(lapply(variables_levante, function(v) {
  vd <- paste0(v, "_desv")
  x <- pred[origen_residuo == "oof_train", get(vd)]
  mediana <- median(x, na.rm = TRUE)
  x[!is.finite(x)] <- mediana
  media <- mean(x)
  desvio <- sd(x)
  if (!is.finite(desvio) || desvio == 0) desvio <- 1
  z <- pred[[vd]]
  z[!is.finite(z)] <- mediana
  pred[, (paste0("z_", vd)) := (z - media) / desvio]
  data.table(variable = v, mediana = mediana, media = media, desvio = desvio)
}))

pred[, periodo_analisis := fifelse(
  origen_residuo == "oof_train", "oof_train", as.character(split_modelo)
)]

ajustar_pendiente <- function(dt, variable, por_barrio = FALSE) {
  zvar <- paste0("z_", variable, "_desv")
  grupos <- if (por_barrio) c("periodo_analisis", "territorio") else "periodo_analisis"
  dt[
    is.finite(get(zvar)) & is.finite(residuo_pearson),
    {
      x <- get(zvar)
      y <- residuo_pearson
      if (uniqueN(x) < 2L) {
        list(
          variable = variable, n = .N, dias = uniqueN(dia_objetivo),
          pendiente = NA_real_, error_std = NA_real_, p_valor = NA_real_,
          correlacion = NA_real_
        )
      } else {
        fit <- lm(y ~ x)
        cf <- summary(fit)$coefficients
        .(
          variable = variable,
          n = .N,
          dias = uniqueN(dia_objetivo),
          pendiente = unname(coef(fit)[[2L]]),
          error_std = cf[2L, 2L],
          p_valor = cf[2L, 4L],
          correlacion = cor(x, y)
        )
      }
    },
    by = grupos
  ]
}

pendientes_globales <- rbindlist(lapply(
  variables_levante, function(v) ajustar_pendiente(pred, v, FALSE)
))
pendientes_barrio <- rbindlist(lapply(
  variables_levante, function(v) ajustar_pendiente(pred, v, TRUE)
))

# Curvas empiricas en deciles definidos sobre OOF train para cada variable.
curvas <- rbindlist(lapply(variables_levante, function(v) {
  zvar <- paste0("z_", v, "_desv")
  cortes <- unique(quantile(
    pred[periodo_analisis == "oof_train", get(zvar)],
    probs = seq(0, 1, 0.1), na.rm = TRUE
  ))
  if (length(cortes) < 3L) return(NULL)
  tmp <- pred[is.finite(get(zvar))]
  tmp[, bin := cut(get(zvar), breaks = cortes, include.lowest = TRUE)]
  tmp[!is.na(bin), .(
    variable = v,
    n = .N,
    valor_medio_z = mean(get(zvar)),
    residuo_pearson_medio = mean(residuo_pearson),
    residuo_clusters_medio = mean(residuo_clusters)
  ), by = .(periodo_analisis, bin)]
}))

metricas_base <- pred[, {
  error <- esperado_base - clusters_con_reclamo
  .(
    filas = .N,
    dias = uniqueN(dia_objetivo),
    sesgo_cluster_barrio = mean(error),
    mae_cluster_barrio = mean(abs(error)),
    rmse_cluster_barrio = sqrt(mean(error^2)),
    media_residuo_pearson = mean(residuo_pearson),
    sd_residuo_pearson = sd(residuo_pearson)
  )
}, by = periodo_analisis]

saveRDS(res_externo$fit, file.path(path_out, "modelo_base_train_completo.rds"))
fwrite(rbindlist(diag_folds), file.path(path_out, "diagnostico_folds.csv"))
fwrite(estandarizacion, file.path(path_out, "estandarizacion_variables_levante.csv"))
fwrite(pred, file.path(path_out, "residuos_barrio_dia.csv"))
fwrite(metricas_base, file.path(path_out, "metricas_modelo_base.csv"))
fwrite(pendientes_globales, file.path(path_out, "pendientes_globales.csv"))
fwrite(pendientes_barrio, file.path(path_out, "pendientes_por_barrio.csv"))
fwrite(curvas, file.path(path_out, "curvas_empiricas_deciles.csv"))

print(rbindlist(diag_folds))
print(metricas_base)
print(pendientes_globales[periodo_analisis == "oof_train"][order(-abs(correlacion))])
