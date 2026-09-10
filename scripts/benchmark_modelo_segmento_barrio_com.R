library(arrow)
library(data.table)
library(mgcv)

path_pred <- "app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia/modelo_id=com_reclamo"
path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
path_segmento <- "data/processed/cluster_territorial/cluster_segmento_censal"
path_modelo_com <- "data/processed/modelos/logistico_cluster_dia_reducido_reclamos_d2/modelo_logistico_reducido.rds"
path_out <- "outputs/benchmark_modelo_segmento_barrio_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

tiempos <- list()
medir <- function(etapa, expresion) {
  gc()
  t <- system.time(valor <- force(expresion))
  tiempos[[length(tiempos) + 1L]] <<- data.table(
    etapa = etapa,
    segundos_usuario = unname(t[["user.self"]]),
    segundos_sistema = unname(t[["sys.self"]]),
    segundos_transcurridos = unname(t[["elapsed"]])
  )
  valor
}

modelo_com <- readRDS(path_modelo_com)

pred <- medir("leer_predicciones", {
  as.data.table(as.data.frame(
    open_dataset(path_pred) |>
      dplyr::select(
        cluster_id, dia_objetivo, version_cluster, pred_prob,
        tuvo_reclamo_observado
      ) |>
      dplyr::collect()
  ))
})
pred[, dia_objetivo := as.IDate(dia_objetivo)]
pred <- pred[!is.na(tuvo_reclamo_observado)]

version_cluster_obj <- unique(pred$version_cluster)
if (length(version_cluster_obj) != 1L) stop("Se esperaba una version_cluster")

ratio <- medir("leer_ratio", {
  as.data.table(as.data.frame(
    open_dataset(path_features) |>
      dplyr::filter(version_cluster %in% version_cluster_obj) |>
      dplyr::select(
        cluster_id, dia, version_cluster,
        mean_ratio_tiempo_periodo_pred
      ) |>
      dplyr::collect()
  ))
})
setnames(ratio, "dia", "dia_objetivo")
ratio[, dia_objetivo := as.IDate(dia_objetivo)]

admin <- as.data.table(as.data.frame(open_dataset(path_admin)))[
  version_cluster == version_cluster_obj,
  .(cluster_id, barrio = nombre_barrio_ine)
]
segmento <- as.data.table(as.data.frame(open_dataset(path_segmento)))[
  version_cluster == version_cluster_obj,
  .(cluster_id, segmento = as.character(codseg_centroide))
]
geo <- segmento[admin, on = "cluster_id"]
if (anyDuplicated(geo$cluster_id)) stop("Cluster duplicado en geografia")

datos <- medir("unir_cluster_dia", {
  x <- ratio[pred, on = c("cluster_id", "dia_objetivo", "version_cluster")]
  geo[x, on = "cluster_id"]
})
datos[is.na(barrio) | !nzchar(barrio), barrio := "SIN_BARRIO"]
datos[is.na(segmento) | !nzchar(segmento), segmento := "SIN_SEGMENTO"]

base <- medir("agregar_segmento_dia", {
  datos[, {
    ratio_valido <- mean_ratio_tiempo_periodo_pred[
      is.finite(mean_ratio_tiempo_periodo_pred)
    ]
    exceso <- pmax(ratio_valido - 1, 0)
    .(
      n_clusters = .N,
      clusters_con_reclamo = sum(tuvo_reclamo_observado == 1L),
      suma_scores = sum(pred_prob, na.rm = TRUE),
      score_medio = mean(pred_prob, na.rm = TRUE),
      carga_exceso_media = if (length(exceso)) mean(exceso) else NA_real_,
      ratio_medio = if (length(ratio_valido)) mean(ratio_valido) else NA_real_
    )
  }, by = .(dia_objetivo, barrio, segmento)]
})

top_barrio <- medir("agregar_top_scores_barrio_dia", {
  datos[order(barrio, dia_objetivo, -pred_prob), {
    scores <- pred_prob[is.finite(pred_prob)]
    .(
      suma_scores_barrio = sum(scores),
      score_p90_barrio = as.numeric(quantile(scores, 0.90, type = 8)),
      suma_top20_barrio = sum(head(scores, 20L)),
      media_top20_barrio = mean(head(scores, 20L)),
      suma_top30_barrio = sum(head(scores, 30L)),
      media_top30_barrio = mean(head(scores, 30L))
    )
  }, by = .(dia_objetivo, barrio)]
})
base[top_barrio, on = c("dia_objetivo", "barrio"), `:=`(
  suma_scores_barrio = i.suma_scores_barrio,
  score_p90_barrio = i.score_p90_barrio,
  suma_top20_barrio = i.suma_top20_barrio,
  media_top20_barrio = i.media_top20_barrio,
  suma_top30_barrio = i.suma_top30_barrio,
  media_top30_barrio = i.media_top30_barrio
)]

base[, anio_mes := year(dia_objetivo) * 100L + month(dia_objetivo)]
base[, split_modelo := fcase(
  anio_mes %in% modelo_com$meses_train, "entrenamiento",
  anio_mes %in% modelo_com$meses_validacion, "validacion",
  anio_mes %in% modelo_com$meses_test, "test",
  default = "fuera_split"
)]
base[, `:=`(
  barrio = factor(barrio),
  segmento = factor(segmento),
  dia_semana = factor(weekdays(dia_objetivo)),
  prop_clusters_reclamo = clusters_con_reclamo / n_clusters
)]

x_train <- base[split_modelo == "entrenamiento", carga_exceso_media]
mediana_exceso <- median(x_train, na.rm = TRUE)
x_train[!is.finite(x_train)] <- mediana_exceso
media_exceso <- mean(x_train)
sd_exceso <- sd(x_train)
x <- base$carga_exceso_media
x[!is.finite(x)] <- mediana_exceso
base[, z_carga_exceso_media := (x - media_exceso) / sd_exceso]

formulas <- list(
  A0_jerarquia = prop_clusters_reclamo ~ dia_semana +
    s(barrio, bs = "re") + s(segmento, bs = "re"),
  A1_exceso_lineal = prop_clusters_reclamo ~ dia_semana +
    z_carga_exceso_media +
    s(barrio, bs = "re") + s(segmento, bs = "re"),
  A2_exceso_suave = prop_clusters_reclamo ~ dia_semana +
    s(z_carga_exceso_media, k = 6, bs = "cr") +
    s(barrio, bs = "re") + s(segmento, bs = "re")
)

train <- base[split_modelo == "entrenamiento"]
fits <- list()
diagnosticos <- list()
for (escenario in names(formulas)) {
  fit <- medir(paste0("ajustar_", escenario), {
    bam(
      formulas[[escenario]],
      data = train,
      family = binomial(),
      weights = n_clusters,
      method = "fREML",
      discrete = TRUE,
      nthreads = 2L
    )
  })
  fits[[escenario]] <- fit
  diagnosticos[[escenario]] <- data.table(
    escenario = escenario,
    convergencia = if (isTRUE(fit$converged)) "OK" else "REVISAR",
    AIC = AIC(fit),
    logLik = as.numeric(logLik(fit)),
    coeficientes = length(coef(fit))
  )
  saveRDS(fit, file.path(path_out, paste0("modelo_", escenario, ".rds")))
}

inventario <- data.table(
  filas_cluster_dia = nrow(datos),
  filas_segmento_dia = nrow(base),
  dias = uniqueN(base$dia_objetivo),
  barrios = uniqueN(base$barrio),
  segmentos = uniqueN(base$segmento),
  mediana_clusters_segmento_dia = median(base$n_clusters),
  p90_clusters_segmento_dia = as.numeric(quantile(base$n_clusters, 0.90)),
  pct_filas_target_cero = 100 * mean(base$clusters_con_reclamo == 0),
  memoria_base_mb = as.numeric(object.size(base)) / 1024^2
)

fwrite(base, file.path(path_out, "base_segmento_dia.csv"))
fwrite(inventario, file.path(path_out, "inventario.csv"))
fwrite(rbindlist(tiempos), file.path(path_out, "tiempos.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnostico_modelos.csv"))

print(inventario)
print(rbindlist(tiempos))
print(rbindlist(diagnosticos))
