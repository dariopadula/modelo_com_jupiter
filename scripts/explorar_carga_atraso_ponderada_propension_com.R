library(arrow)
library(data.table)

path_pred <- paste0(
  "app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia/",
  "modelo_id=com_reclamo"
)
path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
path_segmento <- "data/processed/cluster_territorial/cluster_segmento_censal"
path_modelo <- paste0(
  "data/processed/modelos/logistico_cluster_dia_reducido_reclamos_d2/",
  "modelo_logistico_reducido.rds"
)
path_out <- "outputs/exploracion_carga_atraso_ponderada_propension_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

ventana <- 90L
rezago <- 2L
fuerza_prior_barrio <- 30
tope_exceso <- 3

pred <- as.data.table(as.data.frame(
  open_dataset(path_pred) |>
    dplyr::select(
      cluster_id, dia_objetivo, version_cluster, tuvo_reclamo_observado
    ) |>
    dplyr::collect()
))
pred[, dia_objetivo := as.IDate(dia_objetivo)]
pred <- pred[!is.na(tuvo_reclamo_observado)]
pred[, y := as.integer(tuvo_reclamo_observado == 1L)]

version_cluster_obj <- unique(pred$version_cluster)
if (length(version_cluster_obj) != 1L) stop("Se esperaba una version_cluster")

ratio <- as.data.table(as.data.frame(
  open_dataset(path_features) |>
    dplyr::filter(version_cluster %in% version_cluster_obj) |>
    dplyr::select(
      cluster_id, dia, version_cluster,
      mean_tiempo_desde_ultimo_levante_pred,
      mean_levante_periodo,
      mean_ratio_tiempo_periodo_pred
    ) |>
    dplyr::collect()
))
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

datos <- ratio[pred, on = c("cluster_id", "dia_objetivo", "version_cluster")]
datos <- geo[datos, on = "cluster_id"]
datos[is.na(barrio) | !nzchar(barrio), barrio := "SIN_BARRIO"]
datos[is.na(segmento) | !nzchar(segmento), segmento := "SIN_SEGMENTO"]
setorder(datos, cluster_id, dia_objetivo)

# Historia del cluster en las 90 observaciones previas, cerrada en D-2.
# Se auditan los saltos de fecha para cuantificar la diferencia entre filas y
# dias calendario antes de promover esta construccion.
datos[, `:=`(
  eventos_cluster_90 = shift(frollsum(y, ventana, align = "right"), rezago),
  exposicion_cluster_90 = shift(
    frollsum(rep(1, .N), ventana, align = "right"), rezago
  ),
  salto_dias = as.integer(dia_objetivo - shift(dia_objetivo))
), by = cluster_id]

barrio_dia <- datos[, .(
  eventos = sum(y),
  exposicion = .N
), by = .(barrio, dia_objetivo)]
setorder(barrio_dia, barrio, dia_objetivo)
barrio_dia[, `:=`(
  eventos_barrio_90 = shift(
    frollsum(eventos, ventana, align = "right"), rezago
  ),
  exposicion_barrio_90 = shift(
    frollsum(exposicion, ventana, align = "right"), rezago
  )
), by = barrio]
barrio_dia[, q_barrio_90 := eventos_barrio_90 / exposicion_barrio_90]

datos[barrio_dia, on = c("barrio", "dia_objetivo"), `:=`(
  q_barrio_90 = i.q_barrio_90
)]
datos[, q_cluster_90_eb := (
  eventos_cluster_90 + fuerza_prior_barrio * q_barrio_90
) / (exposicion_cluster_90 + fuerza_prior_barrio)]

# Primera funcion de atraso para la auditoria: exceso positivo con saturacion.
datos[, exceso := pmax(mean_ratio_tiempo_periodo_pred - 1, 0)]
datos[, h_exceso := pmin(exceso, tope_exceso)]
datos[, w := q_cluster_90_eb * h_exceso]

modelo <- readRDS(path_modelo)
datos[, anio_mes := year(dia_objetivo) * 100L + month(dia_objetivo)]
datos[, split_modelo := fcase(
  anio_mes %in% modelo$meses_train, "entrenamiento",
  anio_mes %in% modelo$meses_validacion, "validacion",
  anio_mes %in% modelo$meses_test, "test",
  default = "fuera_split"
)]
datos[, dia_semana := weekdays(dia_objetivo)]

auditables <- datos[
  is.finite(q_cluster_90_eb) & is.finite(h_exceso) &
    split_modelo %in% c("entrenamiento", "validacion", "test")
]

resumir_nivel <- function(dt, grupos, nivel) {
  out <- dt[order(-w), {
    k <- max(1L, ceiling(.N * 0.20))
    .(
      n_clusters = .N,
      observado = sum(y),
      media_q = mean(q_cluster_90_eb),
      rms_q = sqrt(mean(q_cluster_90_eb^2)),
      media_tiempo_levante = mean(
        mean_tiempo_desde_ultimo_levante_pred, na.rm = TRUE
      ),
      media_periodo = mean(mean_levante_periodo, na.rm = TRUE),
      media_ratio = mean(mean_ratio_tiempo_periodo_pred, na.rm = TRUE),
      suma_h = sum(h_exceso),
      media_h = mean(h_exceso),
      suma_w = sum(w),
      media_w = mean(w),
      rms_w = sqrt(mean(w^2)),
      media_top20pct_w = mean(head(w, k)),
      p90_w = as.numeric(quantile(w, 0.90, type = 8)),
      max_w = max(w),
      prop_exceso_positivo = mean(h_exceso > 0),
      prop_exceso_mayor_1 = mean(h_exceso > 1)
    )
  }, by = grupos]
  out[, nivel := nivel]
  out
}

agg_ciudad <- resumir_nivel(
  auditables, c("dia_objetivo", "split_modelo", "dia_semana"), "ciudad"
)
agg_barrio <- resumir_nivel(
  auditables,
  c("dia_objetivo", "split_modelo", "dia_semana", "barrio"),
  "barrio"
)
agg_segmento <- resumir_nivel(
  auditables,
  c("dia_objetivo", "split_modelo", "dia_semana", "barrio", "segmento"),
  "segmento"
)

correlaciones_n <- rbindlist(lapply(list(
  ciudad = agg_ciudad,
  barrio = agg_barrio,
  segmento = agg_segmento
), function(x) {
  x[, .(
    filas = .N,
    mediana_n_clusters = median(n_clusters),
    cor_n_suma_h = cor(n_clusters, suma_h),
    cor_n_media_h = cor(n_clusters, media_h),
    cor_n_suma_w = cor(n_clusters, suma_w),
    cor_n_media_w = cor(n_clusters, media_w),
    cor_n_rms_w = cor(n_clusters, rms_w),
    cor_n_top20pct_w = cor(n_clusters, media_top20pct_w)
  ), by = nivel]
}), use.names = TRUE)

# Residuo estructural simple de ciudad: promedio de entrenamiento por dia de
# semana. Se usa solo para comparar indicadores, no como modelo candidato.
baseline_semana <- agg_ciudad[split_modelo == "entrenamiento", .(
  esperado_estructural = mean(observado)
), by = dia_semana]
agg_ciudad[baseline_semana, on = "dia_semana",
  esperado_estructural := i.esperado_estructural]
agg_ciudad[, residuo_estructural := observado - esperado_estructural]

indicadores <- c(
  "suma_h", "media_h", "suma_w", "media_w", "rms_w",
  "media_top20pct_w", "p90_w", "max_w", "prop_exceso_positivo",
  "prop_exceso_mayor_1"
)
cor_ciudad <- rbindlist(lapply(indicadores, function(v) {
  agg_ciudad[split_modelo %in% c("validacion", "test"), .(
    indicador = v,
    correlacion_observado = cor(get(v), observado),
    correlacion_residuo_estructural = cor(get(v), residuo_estructural)
  )]
}))

diag_propension <- auditables[, .(
  filas = .N,
  clusters = uniqueN(cluster_id),
  dias = uniqueN(dia_objetivo),
  prevalencia = mean(y),
  media_q = mean(q_cluster_90_eb),
  sd_q = sd(q_cluster_90_eb),
  p10_q = as.numeric(quantile(q_cluster_90_eb, 0.10)),
  mediana_q = median(q_cluster_90_eb),
  p90_q = as.numeric(quantile(q_cluster_90_eb, 0.90)),
  brier_q = mean((q_cluster_90_eb - y)^2),
  cor_q_y = cor(q_cluster_90_eb, y)
), by = split_modelo]

cobertura <- datos[, .(
  filas = .N,
  pct_q_disponible = 100 * mean(is.finite(q_cluster_90_eb)),
  pct_ratio_disponible = 100 * mean(is.finite(mean_ratio_tiempo_periodo_pred)),
  pct_ambos_disponibles = 100 * mean(
    is.finite(q_cluster_90_eb) & is.finite(mean_ratio_tiempo_periodo_pred)
  ),
  pct_saltos_mayores_1_dia = 100 * mean(salto_dias > 1, na.rm = TRUE)
), by = split_modelo]

fwrite(cobertura, file.path(path_out, "cobertura.csv"))
fwrite(diag_propension, file.path(path_out, "diagnostico_propension.csv"))
fwrite(correlaciones_n, file.path(path_out, "dependencia_tamano.csv"))
fwrite(cor_ciudad, file.path(path_out, "correlaciones_ciudad.csv"))
fwrite(agg_ciudad, file.path(path_out, "indicadores_ciudad_dia.csv"))
fwrite(agg_barrio, file.path(path_out, "indicadores_barrio_dia.csv"))
fwrite(agg_segmento, file.path(path_out, "indicadores_segmento_dia.csv"))
fwrite(data.table(
  ventana = ventana,
  rezago = rezago,
  fuerza_prior_barrio = fuerza_prior_barrio,
  tope_exceso = tope_exceso
), file.path(path_out, "parametros.csv"))

print(cobertura)
print(diag_propension)
print(correlaciones_n)
print(cor_ciudad[order(-abs(correlacion_residuo_estructural))])
