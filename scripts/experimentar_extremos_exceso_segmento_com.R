library(arrow)
library(data.table)
library(mgcv)

path_base <- file.path(
  "outputs", "benchmark_modelo_segmento_barrio_com", "base_segmento_dia.csv"
)
path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_segmento <- "data/processed/cluster_territorial/cluster_segmento_censal"
path_top_scores <- file.path(
  "outputs", "experimento_top20pct_interaccion_exceso_com",
  "top20pct_barrio_dia.csv"
)
path_propension <- file.path(
  "outputs", "experimento_propension_barrio_exceso_com",
  "propensiones_barrio_dia.csv"
)
path_out <- "outputs/experimento_extremos_exceso_segmento_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base <- fread(path_base)
base[, dia_objetivo := as.IDate(dia_objetivo)]
base[, segmento := as.character(segmento)]
fecha_min <- min(base$dia_objetivo)
fecha_max <- max(base$dia_objetivo)

segmento <- as.data.table(as.data.frame(open_dataset(path_segmento)))
version_cluster_obj <- unique(segmento$version_cluster)
if (length(version_cluster_obj) != 1L) stop("Se esperaba una version_cluster")
segmento <- segmento[, .(
  cluster_id,
  segmento = as.character(codseg_centroide)
)]

ratio <- as.data.table(as.data.frame(
  open_dataset(path_features) |>
    dplyr::filter(
      version_cluster %in% version_cluster_obj,
      dia >= fecha_min,
      dia <= fecha_max
    ) |>
    dplyr::select(
      cluster_id, dia, mean_ratio_tiempo_periodo_pred
    ) |>
    dplyr::collect()
))
setnames(ratio, "dia", "dia_objetivo")
ratio[, dia_objetivo := as.IDate(dia_objetivo)]
ratio <- segmento[ratio, on = "cluster_id"]
ratio <- ratio[!is.na(segmento) & is.finite(mean_ratio_tiempo_periodo_pred)]
ratio[, exceso_cluster := pmax(mean_ratio_tiempo_periodo_pred - 1, 0)]

extremos_segmento <- ratio[order(segmento, dia_objetivo, -exceso_cluster), {
  k <- max(1L, ceiling(.N * 0.20))
  top <- head(exceso_cluster, k)
  .(
    n_ratio_segmento = .N,
    n_top20pct_exceso_segmento = k,
    media_top20pct_exceso_segmento = mean(top),
    suma_top20pct_exceso_segmento = sum(top),
    p90_exceso_segmento = as.numeric(quantile(exceso_cluster, 0.90, type = 8)),
    max_exceso_segmento = max(exceso_cluster)
  )
}, by = .(segmento, dia_objetivo)]

base[extremos_segmento, on = c("segmento", "dia_objetivo"), `:=`(
  n_ratio_segmento = i.n_ratio_segmento,
  n_top20pct_exceso_segmento = i.n_top20pct_exceso_segmento,
  media_top20pct_exceso_segmento = i.media_top20pct_exceso_segmento,
  suma_top20pct_exceso_segmento = i.suma_top20pct_exceso_segmento,
  p90_exceso_segmento = i.p90_exceso_segmento,
  max_exceso_segmento = i.max_exceso_segmento
)]

top_scores <- fread(path_top_scores)
top_scores[, dia_objetivo := as.IDate(dia_objetivo)]
base[top_scores, on = c("barrio", "dia_objetivo"), `:=`(
  media_top20pct_barrio = i.media_top20pct_barrio
)]

propension <- fread(path_propension)
propension[, dia_objetivo := as.IDate(dia_objetivo)]
base[propension, on = c("barrio", "dia_objetivo"), `:=`(
  propension_30d = i.propension_30d
)]

base <- base[
  is.finite(media_top20pct_exceso_segmento) &
    is.finite(media_top20pct_barrio) &
    is.finite(propension_30d)
]
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
  "carga_exceso_media",
  "media_top20pct_exceso_segmento",
  "media_top20pct_barrio",
  "propension_30d"
), function(v) estandarizar_train(base, v)))

estructura <- ~ dia_semana + z_media_top20pct_barrio +
  s(barrio, bs = "re") + s(segmento, bs = "re")

formulas <- list(
  E0_exceso_medio = prop_clusters_reclamo ~ dia_semana +
    z_media_top20pct_barrio +
    s(z_carga_exceso_media, k = 6, bs = "cr") +
    s(barrio, bs = "re") + s(segmento, bs = "re"),
  E1_extremo_segmento = prop_clusters_reclamo ~ dia_semana +
    z_media_top20pct_barrio +
    s(z_media_top20pct_exceso_segmento, k = 6, bs = "cr") +
    s(barrio, bs = "re") + s(segmento, bs = "re"),
  E2_medio_mas_extremo = prop_clusters_reclamo ~ dia_semana +
    z_media_top20pct_barrio +
    s(z_carga_exceso_media, k = 6, bs = "cr") +
    s(z_media_top20pct_exceso_segmento, k = 6, bs = "cr") +
    s(barrio, bs = "re") + s(segmento, bs = "re"),
  E3_extremo_x_propension = prop_clusters_reclamo ~ dia_semana +
    z_media_top20pct_barrio + z_propension_30d +
    s(z_carga_exceso_media, k = 6, bs = "cr") +
    s(z_media_top20pct_exceso_segmento, k = 6, bs = "cr") +
    z_media_top20pct_exceso_segmento:z_propension_30d +
    s(barrio, bs = "re") + s(segmento, bs = "re"),
  E4_extremo_x_score = prop_clusters_reclamo ~ dia_semana +
    z_media_top20pct_barrio +
    s(z_carga_exceso_media, k = 6, bs = "cr") +
    s(z_media_top20pct_exceso_segmento, k = 6, bs = "cr") +
    z_media_top20pct_exceso_segmento:z_media_top20pct_barrio +
    s(barrio, bs = "re") + s(segmento, bs = "re")
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
    "top20pct_exceso.*:|:.*top20pct_exceso",
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

metricas_periodo <- metricas_fun(pred_dia, c("escenario", "split_modelo"))
metricas_combinadas <- metricas_fun(pred_dia, "escenario")[
  , split_modelo := "validacion + test"
]
setcolorder(metricas_combinadas, names(metricas_periodo))
metricas_periodo <- rbindlist(list(metricas_periodo, metricas_combinadas))
metricas_mensuales <- metricas_fun(pred_dia, c("escenario", "mes"))

inventario_top <- base[, .(
  filas_segmento_dia = .N,
  mediana_clusters_ratio = median(n_ratio_segmento),
  mediana_clusters_top20pct = median(n_top20pct_exceso_segmento),
  p90_clusters_top20pct = as.numeric(quantile(n_top20pct_exceso_segmento, 0.90)),
  pct_top_un_cluster = 100 * mean(n_top20pct_exceso_segmento == 1L),
  pct_top_hasta_dos = 100 * mean(n_top20pct_exceso_segmento <= 2L)
)]

fwrite(extremos_segmento, file.path(path_out, "extremos_segmento_dia.csv"))
fwrite(inventario_top, file.path(path_out, "inventario_top20pct.csv"))
fwrite(prep, file.path(path_out, "preparacion_variables.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnostico_modelos.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas_periodo, file.path(path_out, "metricas_periodo.csv"))
fwrite(metricas_mensuales, file.path(path_out, "metricas_mensuales.csv"))

print(inventario_top)
print(rbindlist(diagnosticos))
print(metricas_periodo[split_modelo == "validacion"][order(rmse)])
print(metricas_periodo[split_modelo == "test"][order(rmse)])
