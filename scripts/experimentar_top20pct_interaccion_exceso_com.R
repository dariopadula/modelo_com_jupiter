library(arrow)
library(data.table)
library(mgcv)

path_base <- file.path(
  "outputs", "benchmark_modelo_segmento_barrio_com", "base_segmento_dia.csv"
)
path_pred <- "app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia/modelo_id=com_reclamo"
path_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
path_out <- "outputs/experimento_top20pct_interaccion_exceso_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base <- fread(path_base)
base[, dia_objetivo := as.IDate(dia_objetivo)]

pred <- as.data.table(as.data.frame(
  open_dataset(path_pred) |>
    dplyr::select(
      cluster_id, dia_objetivo, version_cluster,
      pred_prob, tuvo_reclamo_observado
    ) |>
    dplyr::collect()
))
pred[, dia_objetivo := as.IDate(dia_objetivo)]
pred <- pred[!is.na(tuvo_reclamo_observado) & is.finite(pred_prob)]
version_cluster_obj <- unique(pred$version_cluster)
if (length(version_cluster_obj) != 1L) stop("Se esperaba una version_cluster")

admin <- as.data.table(as.data.frame(open_dataset(path_admin)))[
  version_cluster == version_cluster_obj,
  .(cluster_id, barrio = nombre_barrio_ine)
]
pred <- admin[pred, on = "cluster_id"]
pred[is.na(barrio) | !nzchar(barrio), barrio := "SIN_BARRIO"]

top20pct <- pred[order(barrio, dia_objetivo, -pred_prob), {
  k <- max(1L, ceiling(.N * 0.20))
  top <- head(pred_prob, k)
  .(
    n_clusters_barrio = .N,
    n_top20pct = k,
    media_top20pct_barrio = mean(top),
    suma_top20pct_barrio = sum(top)
  )
}, by = .(barrio, dia_objetivo)]

base[top20pct, on = c("barrio", "dia_objetivo"), `:=`(
  n_clusters_barrio = i.n_clusters_barrio,
  n_top20pct = i.n_top20pct,
  media_top20pct_barrio = i.media_top20pct_barrio,
  suma_top20pct_barrio = i.suma_top20pct_barrio
)]
if (base[, anyNA(media_top20pct_barrio)]) stop("Falta top-20% en la base")

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

prep <- rbindlist(lapply(c(
  "carga_exceso_media", "suma_top20_barrio",
  "media_top20pct_barrio", "suma_top20pct_barrio"
), function(v) estandarizar_train(base, v)))

formula_b0 <- prop_clusters_reclamo ~ dia_semana +
  s(z_carga_exceso_media, k = 6, bs = "cr") +
  z_suma_top20_barrio +
  s(barrio, bs = "re") + s(segmento, bs = "re")

formula_b1 <- prop_clusters_reclamo ~ dia_semana +
  s(z_carga_exceso_media, k = 6, bs = "cr") +
  z_media_top20pct_barrio +
  s(barrio, bs = "re") + s(segmento, bs = "re")

formulas <- list(
  B0_top20_fijo = formula_b0,
  B1_media_top20pct = formula_b1,
  B2_top20_fijo_interaccion = update(
    formula_b0,
    . ~ . + z_carga_exceso_media:z_suma_top20_barrio
  ),
  B3_top20pct_interaccion = update(
    formula_b1,
    . ~ . + z_carga_exceso_media:z_media_top20pct_barrio
  )
)

train <- base[split_modelo == "entrenamiento"]
evaluacion <- base[split_modelo %in% c("validacion", "test")]
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
    dia_objetivo, split_modelo, barrio, segmento,
    n_clusters, clusters_con_reclamo
  )]
  pred[, `:=`(
    escenario = escenario,
    prob_predicha = prob,
    clusters_esperados = n_clusters * prob
  )]
  predicciones[[escenario]] <- pred

  cf <- coef(fit)
  V <- vcov(fit)
  termino_interaccion <- grep(
    "top20.*:.*carga_exceso|carga_exceso.*:.*top20",
    names(cf), value = TRUE
  )
  if (length(termino_interaccion)) {
    est <- unname(cf[termino_interaccion[[1L]]])
    se <- sqrt(diag(V))[termino_interaccion[[1L]]]
  } else {
    est <- se <- NA_real_
  }
  diagnosticos[[escenario]] <- data.table(
    escenario = escenario,
    convergencia = if (isTRUE(fit$converged)) "OK" else "REVISAR",
    AIC = AIC(fit),
    logLik = as.numeric(logLik(fit)),
    coeficientes = length(coef(fit)),
    segundos_ajuste = unname(tiempo[["elapsed"]]),
    coef_interaccion = est,
    se_interaccion = se,
    z_interaccion = est / se,
    p_interaccion = 2 * pnorm(-abs(est / se))
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
  pred_dia, c("escenario", "split_modelo")
)
metricas_combinadas <- metricas_fun(pred_dia, "escenario")[
  , split_modelo := "validacion + test"
]
setcolorder(metricas_combinadas, names(metricas_periodo))
metricas_periodo <- rbindlist(list(metricas_periodo, metricas_combinadas))
metricas_mensuales <- metricas_fun(pred_dia, c("escenario", "mes"))

fwrite(top20pct, file.path(path_out, "top20pct_barrio_dia.csv"))
fwrite(prep, file.path(path_out, "preparacion_variables.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnostico_modelos.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas_periodo, file.path(path_out, "metricas_periodo.csv"))
fwrite(metricas_mensuales, file.path(path_out, "metricas_mensuales.csv"))

print(rbindlist(diagnosticos))
print(metricas_periodo[split_modelo == "validacion"][order(rmse)])
print(metricas_periodo[split_modelo == "test"][order(rmse)])
