library(data.table)
library(mgcv)

path_base <- file.path(
  "outputs", "benchmark_modelo_segmento_barrio_com", "base_segmento_dia.csv"
)
path_out <- "outputs/comparacion_modelos_segmento_barrio_scores_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base <- fread(path_base)
base[, dia_objetivo := as.IDate(dia_objetivo)]
base[, `:=`(
  barrio = factor(barrio),
  segmento = factor(segmento),
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
    variable = variable, mediana_train = mediana,
    media_train = media, desvio_train = desvio
  )
}

variables_continuas <- c(
  "carga_exceso_media",
  "media_top20_barrio",
  "suma_top20_barrio",
  "media_top30_barrio",
  "suma_top30_barrio",
  "score_p90_barrio",
  "suma_scores_barrio"
)
prep <- rbindlist(lapply(
  variables_continuas, function(v) estandarizar_train(base, v)
))

f_jerarquia <- prop_clusters_reclamo ~ dia_semana +
  s(barrio, bs = "re") + s(segmento, bs = "re")

f_exceso <- prop_clusters_reclamo ~ dia_semana +
  s(z_carga_exceso_media, k = 6, bs = "cr") +
  s(barrio, bs = "re") + s(segmento, bs = "re")

formulas <- list(
  A0_jerarquia = f_jerarquia,
  A1_exceso_lineal = update(
    f_jerarquia, . ~ . + z_carga_exceso_media
  ),
  A2_exceso_suave = f_exceso,
  A3_media_top20 = update(
    f_exceso, . ~ . + z_media_top20_barrio
  ),
  A4_suma_top20 = update(
    f_exceso, . ~ . + z_suma_top20_barrio
  ),
  A5_media_top30 = update(
    f_exceso, . ~ . + z_media_top30_barrio
  ),
  A6_suma_top30 = update(
    f_exceso, . ~ . + z_suma_top30_barrio
  ),
  A7_score_p90 = update(
    f_exceso, . ~ . + z_score_p90_barrio
  ),
  A8_suma_scores = update(
    f_exceso, . ~ . + z_suma_scores_barrio
  )
)

train <- base[split_modelo == "entrenamiento"]
newdata <- as.data.frame(
  base[, setdiff(names(base), "dia_objetivo"), with = FALSE]
)

fits <- list()
predicciones <- list()
diagnosticos <- list()
tiempos <- list()

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
    n_clusters, clusters_con_reclamo, suma_scores
  )]
  pred[, `:=`(
    escenario = escenario,
    prob_predicha = prob,
    clusters_esperados = n_clusters * prob
  )]
  fits[[escenario]] <- fit
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
  observado = sum(clusters_con_reclamo),
  predicho = sum(clusters_esperados),
  suma_scores = sum(suma_scores)
), by = .(escenario, split_modelo, dia_objetivo)]

calcular_metricas_diarias <- function(dt, periodo_nombre) {
  dt[, {
    error <- predicho - observado
    .(
      periodo = periodo_nombre,
      dias = .N,
      media_observada = mean(observado),
      media_predicha = mean(predicho),
      sesgo = mean(error),
      mae = mean(abs(error)),
      rmse = sqrt(mean(error^2)),
      correlacion = cor(observado, predicho),
      sd_observado = sd(observado),
      sd_predicho = sd(predicho),
      razon_sd = sd(predicho) / sd(observado)
    )
  }, by = escenario]
}

metricas <- rbindlist(list(
  calcular_metricas_diarias(pred_dia[split_modelo == "validacion"], "validacion"),
  calcular_metricas_diarias(pred_dia[split_modelo == "test"], "test"),
  calcular_metricas_diarias(
    pred_dia[split_modelo %in% c("validacion", "test")],
    "validacion + test"
  )
))

# Baseline M0: una sola serie diaria, repetida en pred_dia para cada escenario.
m0 <- unique(pred_dia[, .(
  dia_objetivo, split_modelo,
  observado, predicho = suma_scores
)])
metricas_m0 <- rbindlist(list(
  calcular_metricas_diarias(
    m0[split_modelo == "validacion"][, escenario := "M0_suma_scores"],
    "validacion"
  ),
  calcular_metricas_diarias(
    m0[split_modelo == "test"][, escenario := "M0_suma_scores"],
    "test"
  ),
  calcular_metricas_diarias(
    m0[split_modelo %in% c("validacion", "test")][
      , escenario := "M0_suma_scores"
    ],
    "validacion + test"
  )
))
metricas <- rbindlist(list(metricas, metricas_m0), fill = TRUE)

metricas_segmento <- pred[
  split_modelo %in% c("validacion", "test"),
  {
    p <- pmin(pmax(prob_predicha, 1e-15), 1 - 1e-15)
    y <- clusters_con_reclamo
    n <- n_clusters
    .(
      cluster_dias = sum(n),
      logloss = -sum(y * log(p) + (n - y) * log(1 - p)) / sum(n),
      deviance_por_cluster = sum(binomial()$dev.resids(y / n, p, n)) / sum(n)
    )
  },
  by = .(escenario, periodo = split_modelo)
]

fwrite(prep, file.path(path_out, "preparacion_variables.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnostico_modelos.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas, file.path(path_out, "metricas_diarias.csv"))
fwrite(metricas_segmento, file.path(path_out, "metricas_segmento.csv"))

print(rbindlist(diagnosticos))
print(metricas[periodo == "test"][order(rmse)])
print(metricas_segmento[periodo == "test"][order(logloss)])
