library(data.table)
library(mgcv)

path_base <- file.path(
  "outputs", "exploracion_carga_atraso_ponderada_propension_com",
  "indicadores_segmento_dia.csv"
)
path_out <- "outputs/prueba_pendientes_aleatorias_carga_segmento_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base <- fread(path_base)
base[, dia_objetivo := as.IDate(dia_objetivo)]
base <- base[
  split_modelo %in% c("entrenamiento", "validacion", "test") &
    n_clusters > 0 & is.finite(media_h) & is.finite(media_w)
]
base[, `:=`(
  prop_reclamo = observado / n_clusters,
  barrio = factor(barrio),
  segmento = factor(segmento),
  dia_semana = factor(dia_semana)
)]

# La pendiente aleatoria usa la desviacion respecto del nivel habitual de cada
# barrio, aprendido solo en entrenamiento. El efecto global conserva la medida
# original y puede ser no lineal.
referencias <- base[split_modelo == "entrenamiento", .(
  media_h_habitual_barrio = mean(media_h),
  media_w_habitual_barrio = mean(media_w)
), by = barrio]
base[referencias, on = "barrio", `:=`(
  media_h_habitual_barrio = i.media_h_habitual_barrio,
  media_w_habitual_barrio = i.media_w_habitual_barrio
)]
base[, `:=`(
  desv_media_h_barrio = media_h - media_h_habitual_barrio,
  desv_media_w_barrio = media_w - media_w_habitual_barrio
)]

estandarizar_train <- function(dt, variable) {
  x_train <- dt[split_modelo == "entrenamiento", get(variable)]
  media <- mean(x_train)
  desvio <- sd(x_train)
  if (!is.finite(desvio) || desvio == 0) desvio <- 1
  dt[, (paste0("z_", variable)) := (get(variable) - media) / desvio]
  data.table(variable = variable, media_train = media, desvio_train = desvio)
}

preparacion <- rbindlist(lapply(c(
  "media_h", "media_w", "desv_media_h_barrio", "desv_media_w_barrio"
), function(v) estandarizar_train(base, v)))

estructura <- prop_reclamo ~ dia_semana +
  s(barrio, bs = "re") + s(segmento, bs = "re")

formulas <- list(
  U0_atraso_sin_pendiente = update(
    estructura, . ~ . + s(z_media_h, k = 6, bs = "cr")
  ),
  U1_atraso_pendiente_barrio = update(
    estructura,
    . ~ . + s(z_media_h, k = 6, bs = "cr") +
      s(barrio, by = z_desv_media_h_barrio, bs = "re")
  ),
  P0_ponderado_sin_pendiente = update(
    estructura, . ~ . + s(z_media_w, k = 6, bs = "cr")
  ),
  P1_ponderado_pendiente_barrio = update(
    estructura,
    . ~ . + s(z_media_w, k = 6, bs = "cr") +
      s(barrio, by = z_desv_media_w_barrio, bs = "re")
  )
)

train <- base[split_modelo == "entrenamiento"]
evaluacion <- base[split_modelo %in% c("validacion", "test")]
newdata <- as.data.frame(
  evaluacion[, setdiff(names(evaluacion), "dia_objetivo"), with = FALSE]
)

predecir_con_niveles_nuevos <- function(fit, newdata, train) {
  segmentos_train <- unique(as.character(train$segmento))
  barrios_train <- unique(as.character(train$barrio))
  segmento_nuevo <- !as.character(newdata$segmento) %in% segmentos_train
  barrio_nuevo <- !as.character(newdata$barrio) %in% barrios_train
  if (any(barrio_nuevo)) stop("Hay barrios nuevos fuera de entrenamiento")

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

predicciones <- list()
diagnosticos <- list()
for (escenario in names(formulas)) {
  gc()
  tiempo <- system.time({
    fit <- bam(
      formulas[[escenario]],
      data = train,
      family = binomial(),
      weights = n_clusters,
      method = "fREML",
      discrete = TRUE,
      nthreads = 2L
    )
  })
  prob <- predecir_con_niveles_nuevos(fit, newdata, train)
  pred <- evaluacion[, .(
    dia_objetivo, split_modelo, barrio, segmento, n_clusters, observado
  )]
  pred[, `:=`(
    escenario = escenario,
    prob_predicha = prob,
    predicho_segmento = n_clusters * prob
  )]
  predicciones[[escenario]] <- pred

  stab <- summary(fit)$s.table
  fila_pendiente <- grep("barrio.*desv|desv.*barrio", rownames(stab), value = TRUE)
  diagnosticos[[escenario]] <- data.table(
    escenario = escenario,
    convergencia = if (isTRUE(fit$converged)) "OK" else "REVISAR",
    AIC = AIC(fit),
    logLik = as.numeric(logLik(fit)),
    coeficientes = length(coef(fit)),
    edf_pendiente_barrio = if (length(fila_pendiente))
      stab[fila_pendiente[[1L]], "edf"] else NA_real_,
    p_pendiente_barrio = if (length(fila_pendiente))
      stab[fila_pendiente[[1L]], ncol(stab)] else NA_real_,
    segundos_ajuste = unname(tiempo[["elapsed"]])
  )
  saveRDS(fit, file.path(path_out, paste0("modelo_", escenario, ".rds")))
}

pred <- rbindlist(predicciones)
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

metricas_periodo <- metricas_fun(pred_dia, c("escenario", "split_modelo"))
metricas_combinadas <- metricas_fun(pred_dia, "escenario")[
  , split_modelo := "validacion + test"
]
setcolorder(metricas_combinadas, names(metricas_periodo))
metricas_periodo <- rbindlist(list(metricas_periodo, metricas_combinadas))
metricas_mensuales <- metricas_fun(pred_dia, c("escenario", "mes"))

fwrite(preparacion, file.path(path_out, "preparacion_variables.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnostico_modelos.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas_periodo, file.path(path_out, "metricas_periodo.csv"))
fwrite(metricas_mensuales, file.path(path_out, "metricas_mensuales.csv"))

print(rbindlist(diagnosticos))
print(metricas_periodo[split_modelo == "validacion"][order(rmse)])
print(metricas_periodo[split_modelo == "test"][order(rmse)])
print(metricas_periodo[split_modelo == "validacion + test"][order(rmse)])
