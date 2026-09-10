library(arrow)
library(data.table)
library(mgcv)

path_base <- file.path(
  "outputs", "benchmark_modelo_segmento_barrio_com", "base_segmento_dia.csv"
)
path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_segmento <- "data/processed/cluster_territorial/cluster_segmento_censal"
path_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
path_top_scores <- file.path(
  "outputs", "experimento_top20pct_interaccion_exceso_com",
  "top20pct_barrio_dia.csv"
)
path_propension <- file.path(
  "outputs", "experimento_propension_barrio_exceso_com",
  "propensiones_barrio_dia.csv"
)
path_extremos_segmento <- file.path(
  "outputs", "experimento_extremos_exceso_segmento_com",
  "extremos_segmento_dia.csv"
)
path_out <- "outputs/experimento_extremo_exceso_propension_barrio_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base <- fread(path_base)
base[, dia_objetivo := as.IDate(dia_objetivo)]
base[, segmento := as.character(segmento)]
fecha_min <- min(base$dia_objetivo)
fecha_max <- max(base$dia_objetivo)

segmento_cluster <- as.data.table(as.data.frame(open_dataset(path_segmento)))
version_cluster_obj <- unique(segmento_cluster$version_cluster)
if (length(version_cluster_obj) != 1L) stop("Se esperaba una version_cluster")
segmento_cluster <- segmento_cluster[, .(
  cluster_id,
  segmento = as.character(codseg_centroide)
)]
admin <- as.data.table(as.data.frame(open_dataset(path_admin)))[
  version_cluster == version_cluster_obj,
  .(cluster_id, barrio = nombre_barrio_ine)
]
geo <- segmento_cluster[admin, on = "cluster_id"]
if (anyDuplicated(geo$cluster_id)) stop("Cluster duplicado en geografia")
geo[is.na(barrio) | !nzchar(barrio), barrio := "SIN_BARRIO"]

ratio <- as.data.table(as.data.frame(
  open_dataset(path_features) |>
    dplyr::filter(
      version_cluster %in% version_cluster_obj,
      dia >= fecha_min,
      dia <= fecha_max
    ) |>
    dplyr::select(cluster_id, dia, mean_ratio_tiempo_periodo_pred) |>
    dplyr::collect()
))
setnames(ratio, "dia", "dia_objetivo")
ratio[, dia_objetivo := as.IDate(dia_objetivo)]
ratio <- geo[ratio, on = "cluster_id"]
ratio <- ratio[!is.na(barrio) & is.finite(mean_ratio_tiempo_periodo_pred)]
ratio[, exceso_cluster := pmax(mean_ratio_tiempo_periodo_pred - 1, 0)]

extremos_barrio <- ratio[order(barrio, dia_objetivo, -exceso_cluster), {
  k <- max(1L, ceiling(.N * 0.20))
  top <- head(exceso_cluster, k)
  .(
    n_ratio_barrio = .N,
    n_top20pct_exceso_barrio = k,
    media_top20pct_exceso_barrio = mean(top)
  )
}, by = .(barrio, dia_objetivo)]

base[extremos_barrio, on = c("barrio", "dia_objetivo"), `:=`(
  n_ratio_barrio = i.n_ratio_barrio,
  n_top20pct_exceso_barrio = i.n_top20pct_exceso_barrio,
  media_top20pct_exceso_barrio = i.media_top20pct_exceso_barrio
)]

extremos_segmento <- fread(path_extremos_segmento)
extremos_segmento[, `:=`(
  dia_objetivo = as.IDate(dia_objetivo),
  segmento = as.character(segmento)
)]
base[extremos_segmento, on = c("segmento", "dia_objetivo"),
  media_top20pct_exceso_segmento := i.media_top20pct_exceso_segmento]

top_scores <- fread(path_top_scores)
top_scores[, dia_objetivo := as.IDate(dia_objetivo)]
base[top_scores, on = c("barrio", "dia_objetivo"),
  media_top20pct_barrio := i.media_top20pct_barrio]

propension <- fread(path_propension)
propension[, dia_objetivo := as.IDate(dia_objetivo)]
base[propension, on = c("barrio", "dia_objetivo"),
  propension_30d := i.propension_30d]

base <- base[
  is.finite(media_top20pct_exceso_barrio) &
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
    variable = variable,
    mediana_train = mediana,
    media_train = media,
    desvio_train = desvio
  )
}

prep <- rbindlist(lapply(c(
  "media_top20pct_exceso_barrio",
  "media_top20pct_exceso_segmento",
  "media_top20pct_barrio",
  "propension_30d"
), function(v) estandarizar_train(base, v)))

estructura <- prop_clusters_reclamo ~ dia_semana +
  z_media_top20pct_barrio +
  s(barrio, bs = "re") + s(segmento, bs = "re")

formulas <- list(
  E1_segmento_referencia = update(
    estructura,
    . ~ . + s(z_media_top20pct_exceso_segmento, k = 6, bs = "cr")
  ),
  H0_extremo_barrio = update(
    estructura,
    . ~ . + s(z_media_top20pct_exceso_barrio, k = 6, bs = "cr")
  ),
  H1_extremo_barrio_propension = update(
    estructura,
    . ~ . + s(z_media_top20pct_exceso_barrio, k = 6, bs = "cr") +
      z_propension_30d
  ),
  H2_interaccion_barrio = update(
    estructura,
    . ~ . + s(z_media_top20pct_exceso_barrio, k = 6, bs = "cr") +
      z_propension_30d +
      z_media_top20pct_exceso_barrio:z_propension_30d
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

metricas_periodo <- metricas_fun(
  pred_dia, c("escenario", "split_modelo")
)
metricas_combinadas <- metricas_fun(pred_dia, "escenario")[
  , split_modelo := "validacion + test"
]
setcolorder(metricas_combinadas, names(metricas_periodo))
metricas_periodo <- rbindlist(list(metricas_periodo, metricas_combinadas))
metricas_mensuales <- metricas_fun(pred_dia, c("escenario", "mes"))

inventario <- extremos_barrio[, .(
  barrios_dia = .N,
  mediana_clusters_ratio = median(n_ratio_barrio),
  mediana_clusters_top20pct = median(n_top20pct_exceso_barrio),
  p10_clusters_top20pct = as.numeric(quantile(n_top20pct_exceso_barrio, 0.10)),
  p90_clusters_top20pct = as.numeric(quantile(n_top20pct_exceso_barrio, 0.90)),
  pct_top_un_cluster = 100 * mean(n_top20pct_exceso_barrio == 1L)
)]

fwrite(extremos_barrio, file.path(path_out, "extremos_barrio_dia.csv"))
fwrite(inventario, file.path(path_out, "inventario_top20pct.csv"))
fwrite(prep, file.path(path_out, "preparacion_variables.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnostico_modelos.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas_periodo, file.path(path_out, "metricas_periodo.csv"))
fwrite(metricas_mensuales, file.path(path_out, "metricas_mensuales.csv"))

print(inventario)
print(rbindlist(diagnosticos))
print(metricas_periodo[split_modelo == "validacion"][order(rmse)])
print(metricas_periodo[split_modelo == "test"][order(rmse)])
print(metricas_periodo[split_modelo == "validacion + test"][order(rmse)])
