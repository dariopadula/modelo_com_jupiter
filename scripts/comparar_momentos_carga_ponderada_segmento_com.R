library(data.table)
library(mgcv)

path_base <- file.path(
  "outputs", "exploracion_carga_atraso_ponderada_propension_com",
  "indicadores_segmento_dia.csv"
)
path_out <- "outputs/comparacion_momentos_carga_ponderada_segmento_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base <- fread(path_base)
base[, dia_objetivo := as.IDate(dia_objetivo)]
base <- base[
  split_modelo %in% c("entrenamiento", "validacion", "test") &
    n_clusters > 0 & is.finite(media_h) & is.finite(media_w) & is.finite(rms_w)
]
base[, `:=`(
  prop_reclamo = observado / n_clusters,
  barrio = factor(barrio),
  segmento = factor(segmento),
  dia_semana = factor(dia_semana)
)]

estandarizar_train <- function(dt, variable) {
  x_train <- dt[split_modelo == "entrenamiento", get(variable)]
  media <- mean(x_train)
  desvio <- sd(x_train)
  if (!is.finite(desvio) || desvio == 0) desvio <- 1
  dt[, (paste0("z_", variable)) := (get(variable) - media) / desvio]
  data.table(variable = variable, media_train = media, desvio_train = desvio)
}

preparacion <- rbindlist(lapply(
  c("media_h", "media_w", "rms_w"),
  function(v) estandarizar_train(base, v)
))

estructura <- prop_reclamo ~ dia_semana +
  s(barrio, bs = "re") + s(segmento, bs = "re")

# Contraste predefinido por bloques. U1 mide atraso sin ponderar; P1 y P2
# separan primer y segundo momento ponderado; P3 evalua su aporte conjunto.
formulas <- list(
  S0_estructura = estructura,
  U1_media_atraso = update(
    estructura, . ~ . + s(z_media_h, k = 6, bs = "cr")
  ),
  P1_media_ponderada = update(
    estructura, . ~ . + s(z_media_w, k = 6, bs = "cr")
  ),
  P2_rms_ponderado = update(
    estructura, . ~ . + s(z_rms_w, k = 6, bs = "cr")
  ),
  P3_media_mas_rms = update(
    estructura,
    . ~ . + s(z_media_w, k = 6, bs = "cr") +
      s(z_rms_w, k = 6, bs = "cr")
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
  diagnosticos[[escenario]] <- data.table(
    escenario = escenario,
    convergencia = if (isTRUE(fit$converged)) "OK" else "REVISAR",
    AIC = AIC(fit),
    logLik = as.numeric(logLik(fit)),
    coeficientes = length(coef(fit)),
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

cor_momentos_train <- train[, .(
  cor_media_rms = cor(media_w, rms_w),
  cor_media_h_media_w = cor(media_h, media_w),
  cor_media_h_rms_w = cor(media_h, rms_w)
)]

cobertura <- base[, .(
  filas_segmento_dia = .N,
  dias = uniqueN(dia_objetivo),
  barrios = uniqueN(barrio),
  segmentos = uniqueN(segmento),
  mediana_clusters = median(as.numeric(n_clusters))
), by = split_modelo]

fwrite(preparacion, file.path(path_out, "preparacion_variables.csv"))
fwrite(cobertura, file.path(path_out, "cobertura.csv"))
fwrite(cor_momentos_train, file.path(path_out, "correlacion_momentos_train.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnostico_modelos.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas_periodo, file.path(path_out, "metricas_periodo.csv"))
fwrite(metricas_mensuales, file.path(path_out, "metricas_mensuales.csv"))

print(cobertura)
print(cor_momentos_train)
print(rbindlist(diagnosticos))
print(metricas_periodo[split_modelo == "validacion"][order(rmse)])
print(metricas_periodo[split_modelo == "test"][order(rmse)])
print(metricas_periodo[split_modelo == "validacion + test"][order(rmse)])
