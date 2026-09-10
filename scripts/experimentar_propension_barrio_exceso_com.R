library(data.table)
library(mgcv)

path_base <- file.path(
  "outputs", "benchmark_modelo_segmento_barrio_com", "base_segmento_dia.csv"
)
path_a0 <- file.path(
  "outputs", "comparacion_modelos_segmento_barrio_scores_com",
  "modelo_A0_jerarquia.rds"
)
path_out <- "outputs/experimento_propension_barrio_exceso_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base <- fread(path_base)
base[, dia_objetivo := as.IDate(dia_objetivo)]
base[, `:=`(
  barrio = factor(barrio),
  segmento = factor(segmento),
  dia_semana = factor(dia_semana)
)]

# Esperanza estructural de A0 para construir observados/esperados recientes.
modelo_a0 <- readRDS(path_a0)
newdata_a0 <- as.data.frame(
  base[, setdiff(names(base), "dia_objetivo"), with = FALSE]
)
base[, prob_a0 := as.numeric(predict.gam(
  modelo_a0, newdata = newdata_a0, type = "response"
))]

barrio_dia <- base[, .(
  observados = sum(clusters_con_reclamo),
  exposicion = sum(n_clusters),
  esperados_a0 = sum(n_clusters * prob_a0)
), by = .(barrio, dia_objetivo)]
setorder(barrio_dia, barrio, dia_objetivo)

# Ventana [D-31, D-2]: 30 dias completos y sin usar D-1 ni el dia objetivo.
barrio_dia[, `:=`(
  observados_30d = shift(frollsum(observados, 30L, align = "right"), 2L),
  exposicion_30d = shift(frollsum(exposicion, 30L, align = "right"), 2L),
  esperados_a0_30d = shift(frollsum(esperados_a0, 30L, align = "right"), 2L)
), by = barrio]

prevalencia_train <- base[
  split_modelo == "entrenamiento",
  sum(clusters_con_reclamo) / sum(n_clusters)
]
fuerza_prior <- 200
eventos_prior <- prevalencia_train * fuerza_prior

barrio_dia[, propension_30d :=
  (observados_30d + eventos_prior) / (exposicion_30d + fuerza_prior)]
barrio_dia[, propension_relativa_a0_30d := log(
  (observados_30d + eventos_prior) /
    (esperados_a0_30d + eventos_prior)
)]

base[barrio_dia, on = c("barrio", "dia_objetivo"), `:=`(
  observados_30d = i.observados_30d,
  exposicion_30d = i.exposicion_30d,
  esperados_a0_30d = i.esperados_a0_30d,
  propension_30d = i.propension_30d,
  propension_relativa_a0_30d = i.propension_relativa_a0_30d
)]
base <- base[
  is.finite(propension_30d) & is.finite(propension_relativa_a0_30d)
]

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
    variable = variable, mediana_train = mediana,
    media_train = media, desvio_train = desvio
  )
}

prep <- rbindlist(lapply(c(
  "carga_exceso_media", "suma_top20_barrio",
  "propension_30d", "propension_relativa_a0_30d"
), function(v) estandarizar_train(base, v)))

formula_a4 <- prop_clusters_reclamo ~ dia_semana +
  s(z_carga_exceso_media, k = 6, bs = "cr") +
  z_suma_top20_barrio +
  s(barrio, bs = "re") + s(segmento, bs = "re")

formulas <- list(
  P0_A4_referencia = formula_a4,
  P1_tasa_30d = update(
    formula_a4, . ~ . + z_propension_30d
  ),
  P2_tasa_30d_interaccion = update(
    formula_a4,
    . ~ . + z_propension_30d +
      z_carga_exceso_media:z_propension_30d
  ),
  R1_relativa_a0_30d = update(
    formula_a4, . ~ . + z_propension_relativa_a0_30d
  ),
  R2_relativa_a0_30d_interaccion = update(
    formula_a4,
    . ~ . + z_propension_relativa_a0_30d +
      z_carga_exceso_media:z_propension_relativa_a0_30d
  )
)

train <- base[split_modelo == "entrenamiento"]
newdata <- as.data.frame(
  base[, setdiff(names(base), "dia_objetivo"), with = FALSE]
)
fits <- list()
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
  pred <- base[, .(
    dia_objetivo, split_modelo, barrio, segmento,
    n_clusters, clusters_con_reclamo
  )]
  pred[, `:=`(
    escenario = escenario,
    prob_predicha = prob,
    clusters_esperados = n_clusters * prob
  )]
  fits[[escenario]] <- fit
  predicciones[[escenario]] <- pred
  ptab <- summary(fit)$p.table
  termino_interaccion <- grep(
    "propension.*:.*carga_exceso|carga_exceso.*:.*propension",
    rownames(ptab), value = TRUE
  )
  diagnosticos[[escenario]] <- data.table(
    escenario = escenario,
    convergencia = if (isTRUE(fit$converged)) "OK" else "REVISAR",
    AIC = AIC(fit),
    logLik = as.numeric(logLik(fit)),
    coeficientes = length(coef(fit)),
    segundos_ajuste = unname(tiempo[["elapsed"]]),
    coef_interaccion = if (length(termino_interaccion))
      ptab[termino_interaccion[[1L]], "Estimate"] else NA_real_,
    p_interaccion = if (length(termino_interaccion))
      ptab[termino_interaccion[[1L]], "Pr(>|z|)"] else NA_real_
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

metricas_periodo <- metricas_fun(
  pred_dia[split_modelo %in% c("validacion", "test")],
  c("escenario", "split_modelo")
)
metricas_combinadas <- metricas_fun(
  pred_dia[split_modelo %in% c("validacion", "test")],
  "escenario"
)[, split_modelo := "validacion + test"]
setcolorder(metricas_combinadas, names(metricas_periodo))
metricas_periodo <- rbindlist(list(metricas_periodo, metricas_combinadas))
metricas_mensuales <- metricas_fun(pred_dia, c("escenario", "mes"))

fwrite(prep, file.path(path_out, "preparacion_variables.csv"))
fwrite(barrio_dia, file.path(path_out, "propensiones_barrio_dia.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnostico_modelos.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas_periodo, file.path(path_out, "metricas_periodo.csv"))
fwrite(metricas_mensuales, file.path(path_out, "metricas_mensuales.csv"))

print(rbindlist(diagnosticos))
print(metricas_periodo[split_modelo == "test"][order(rmse)])
print(metricas_periodo[split_modelo == "validacion"][order(rmse)])
