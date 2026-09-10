library(data.table)
library(mgcv)

path_base <- file.path(
  "outputs", "benchmark_modelo_segmento_barrio_com", "base_segmento_dia.csv"
)
path_top_scores <- file.path(
  "outputs", "experimento_top20pct_interaccion_exceso_com",
  "top20pct_barrio_dia.csv"
)
path_propension <- file.path(
  "outputs", "experimento_propension_barrio_exceso_com",
  "propensiones_barrio_dia.csv"
)
path_extremos <- file.path(
  "outputs", "experimento_extremo_exceso_propension_barrio_com",
  "extremos_barrio_dia.csv"
)
path_out <- "outputs/experimento_modelo_barrio_dia_interaccion_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base <- fread(path_base)
base[, dia_objetivo := as.IDate(dia_objetivo)]

# Una observacion por barrio y dia. Las cantidades se agregan desde los
# segmentos; calendario y split deben ser unicos dentro de cada barrio-dia.
barrio_dia <- base[, {
  if (uniqueN(split_modelo) != 1L || uniqueN(dia_semana) != 1L) {
    stop("Split o dia de semana no unico dentro de barrio-dia")
  }
  .(
    split_modelo = first(split_modelo),
    dia_semana = first(dia_semana),
    n_clusters = sum(n_clusters),
    clusters_con_reclamo = sum(clusters_con_reclamo)
  )
}, by = .(barrio, dia_objetivo)]
barrio_dia[, prop_clusters_reclamo := clusters_con_reclamo / n_clusters]

top_scores <- fread(path_top_scores)
top_scores[, dia_objetivo := as.IDate(dia_objetivo)]
barrio_dia[top_scores, on = c("barrio", "dia_objetivo"),
  media_top20pct_score := i.media_top20pct_barrio]

propension <- fread(path_propension)
propension[, dia_objetivo := as.IDate(dia_objetivo)]
barrio_dia[propension, on = c("barrio", "dia_objetivo"),
  propension_30d := i.propension_30d]

extremos <- fread(path_extremos)
extremos[, dia_objetivo := as.IDate(dia_objetivo)]
barrio_dia[extremos, on = c("barrio", "dia_objetivo"), `:=`(
  media_top20pct_exceso_barrio = i.media_top20pct_exceso_barrio,
  n_ratio_barrio = i.n_ratio_barrio,
  n_top20pct_exceso_barrio = i.n_top20pct_exceso_barrio
)]

barrio_dia <- barrio_dia[
  n_clusters > 0 &
    is.finite(media_top20pct_score) &
    is.finite(propension_30d) &
    is.finite(media_top20pct_exceso_barrio)
]
barrio_dia[, `:=`(
  barrio = factor(barrio),
  dia_semana = factor(dia_semana)
)]

estandarizar_train <- function(dt, variable) {
  x_train <- dt[split_modelo == "entrenamiento", get(variable)]
  mediana <- median(x_train, na.rm = TRUE)
  x_train[!is.finite(x_train)] <- mediana
  media <- mean(x_train)
  desvio <- sd(x_train)
  if (!is.finite(desvio) || desvio == 0) desvio <- 1
  x <- dt[[variable]]
  x[!is.finite(x)] <- mediana
  dt[, (paste0("z_", variable)) := (x - media) / desvio]
  data.table(
    variable = variable,
    mediana_train = mediana,
    media_train = media,
    desvio_train = desvio
  )
}

prep <- rbindlist(lapply(c(
  "media_top20pct_score",
  "media_top20pct_exceso_barrio",
  "propension_30d"
), function(v) estandarizar_train(barrio_dia, v)))

estructura <- prop_clusters_reclamo ~ dia_semana +
  z_media_top20pct_score + s(barrio, bs = "re")

formulas <- list(
  B0_extremo_barrio = update(
    estructura,
    . ~ . + s(z_media_top20pct_exceso_barrio, k = 6, bs = "cr")
  ),
  B1_extremo_mas_propension = update(
    estructura,
    . ~ . + s(z_media_top20pct_exceso_barrio, k = 6, bs = "cr") +
      z_propension_30d
  ),
  B2_interaccion_barrio = update(
    estructura,
    . ~ . + s(z_media_top20pct_exceso_barrio, k = 6, bs = "cr") +
      z_propension_30d +
      z_media_top20pct_exceso_barrio:z_propension_30d
  )
)

train <- barrio_dia[split_modelo == "entrenamiento"]
evaluacion <- barrio_dia[split_modelo %in% c("validacion", "test")]
newdata <- as.data.frame(
  evaluacion[, setdiff(names(evaluacion), "dia_objetivo"), with = FALSE]
)

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
  prob <- as.numeric(predict.gam(fit, newdata = newdata, type = "response"))
  pred <- evaluacion[, .(
    dia_objetivo, split_modelo, barrio,
    n_clusters, clusters_con_reclamo
  )]
  pred[, `:=`(
    escenario = escenario,
    prob_predicha = prob,
    clusters_esperados = n_clusters * prob
  )]
  predicciones[[escenario]] <- pred

  ptab <- summary(fit)$p.table
  termino <- grep(
    "top20pct_exceso_barrio.*:.*propension|propension.*:.*top20pct_exceso_barrio",
    rownames(ptab), value = TRUE
  )
  diagnosticos[[escenario]] <- data.table(
    escenario = escenario,
    convergencia = if (isTRUE(fit$converged)) "OK" else "REVISAR",
    AIC = AIC(fit),
    logLik = as.numeric(logLik(fit)),
    coeficientes = length(coef(fit)),
    segundos_ajuste = unname(tiempo[["elapsed"]]),
    coef_interaccion = if (length(termino))
      ptab[termino[[1L]], "Estimate"] else NA_real_,
    se_interaccion = if (length(termino))
      ptab[termino[[1L]], "Std. Error"] else NA_real_,
    p_interaccion = if (length(termino))
      ptab[termino[[1L]], "Pr(>|z|)"] else NA_real_
  )
  saveRDS(fit, file.path(path_out, paste0("modelo_", escenario, ".rds")))
}

pred <- rbindlist(predicciones)
pred_dia <- pred[, .(
  observado = sum(clusters_con_reclamo),
  predicho = sum(clusters_esperados)
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

cobertura <- barrio_dia[, .(
  filas_barrio_dia = .N,
  barrios = uniqueN(barrio),
  dias = uniqueN(dia_objetivo),
  mediana_clusters_barrio_dia = median(n_clusters),
  mediana_clusters_top20pct_exceso = median(n_top20pct_exceso_barrio)
), by = split_modelo]

fwrite(barrio_dia, file.path(path_out, "base_barrio_dia.csv"))
fwrite(cobertura, file.path(path_out, "cobertura.csv"))
fwrite(prep, file.path(path_out, "preparacion_variables.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnostico_modelos.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas_periodo, file.path(path_out, "metricas_periodo.csv"))
fwrite(metricas_mensuales, file.path(path_out, "metricas_mensuales.csv"))

print(cobertura)
print(rbindlist(diagnosticos))
print(metricas_periodo[split_modelo == "validacion"][order(rmse)])
print(metricas_periodo[split_modelo == "test"][order(rmse)])
print(metricas_periodo[split_modelo == "validacion + test"][order(rmse)])
