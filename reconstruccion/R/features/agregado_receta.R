# Construye A0 y P3 desde cluster/dia canonico, sin leer publicaciones de la app.
# Preserva ventanas por observaciones (no calendario), D-2 y pertenencia al universo legado.

# Acumula las ultimas n observaciones disponibles a D-rezago, como el recorrido original.
rf_rolling_aggregate <- function(values, n, lag = 2L) {
  accumulated <- cumsum(as.double(values))
  data.table::shift(accumulated, lag, fill = 0) -
    data.table::shift(accumulated, n + lag, fill = 0)
}

# Asigna el split historico explicito y un calendario estable independiente del idioma del SO.
rf_aggregate_calendar <- function(data, calendar) {
  data <- data.table::copy(data)
  month <- as.integer(format(data$dia_objetivo, "%Y%m"))
  data[, split_modelo := data.table::fcase(
    month %in% calendar$train, "entrenamiento", month %in% calendar$valid, "validacion",
    month %in% calendar$test, "test", default = "fuera_split")]
  labels <- c("lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo")
  data[, dia_semana := labels[as.integer(format(dia_objetivo, "%u"))]]
  data
}

# Entradas: features COM canonicas, geografia versionada y calendario de splits/feriados.
# Salida: base A0 sin filtro de levantes y base P3 con universo legado de 90 observaciones.
# Los targets desconocidos siguen NA; nunca se convierten en ceros observados.
rf_build_aggregate <- function(features, geography, calendar, holidays) {
  data <- data.table::copy(data.table::as.data.table(features))
  geo <- data.table::copy(data.table::as.data.table(geography))
  required <- c("version_cluster", "cluster_id", "dia", "tuvo_reclamo",
    "mean_tiempo_desde_ultimo_levante_pred", "mean_levante_periodo", "mean_ratio_tiempo_periodo_pred")
  if (length(setdiff(required, names(data))) ||
      length(setdiff(c("version_cluster", "cluster_id", "barrio", "segmento"), names(geo)))) {
    stop("Faltan columnas canonicas o geograficas del agregado")
  }
  data[, `:=`(version_cluster = as.character(version_cluster), cluster_id = as.character(cluster_id),
    dia = data.table::as.IDate(dia))]
  geo[, `:=`(version_cluster = as.character(version_cluster), cluster_id = as.character(cluster_id))]
  if (anyNA(data[, .(version_cluster, cluster_id, dia)]) ||
      data.table::uniqueN(data$version_cluster) != 1L ||
      anyDuplicated(data[, .(version_cluster, cluster_id, dia)]) ||
      anyDuplicated(geo[, .(version_cluster, cluster_id)])) {
    stop("Claves incompletas/duplicadas o multiples versiones espaciales")
  }
  if (!all(data$tuvo_reclamo[!is.na(data$tuvo_reclamo)] %in% c(0, 1))) {
    stop("El target COM debe ser binario o desconocido")
  }
  spatial_version <- unique(data$version_cluster)
  data <- geo[data, on = c("version_cluster", "cluster_id")]
  data[, `:=`(barrio = as.character(barrio), segmento = as.character(segmento))]
  data[is.na(barrio) | !nzchar(barrio), barrio := "SIN_BARRIO"]
  data[is.na(segmento) | !nzchar(segmento), segmento := "SIN_SEGMENTO"]
  data.table::setnames(data, "dia", "dia_objetivo")
  data.table::setorder(data, cluster_id, dia_objetivo)
  data[, y := as.integer(tuvo_reclamo)]
  a0 <- data[, .(n_clusters = .N, clusters_con_reclamo = sum(y)),
    by = .(dia_objetivo, barrio, segmento)]
  a0[, prop_clusters_reclamo := clusters_con_reclamo / n_clusters]
  a0 <- rf_aggregate_calendar(a0, calendar)

  neighborhood <- data[, .(events = sum(y), exposure = .N), by = .(barrio, dia_objetivo)]
  data.table::setorder(neighborhood, barrio, dia_objetivo)
  global <- neighborhood[, .(events = sum(events), exposure = sum(exposure)), by = dia_objetivo]
  data.table::setorder(global, dia_objetivo)
  # La base usada para OOF del legado excluia historias menores a 90 filas.
  neighborhood[, q90_old := data.table::shift(data.table::frollsum(events, 90L), 2L) /
    data.table::shift(data.table::frollsum(exposure, 90L), 2L), by = barrio]
  data[neighborhood, on = c("barrio", "dia_objetivo"), q90_old := i.q90_old]
  data[, old_history := seq_len(.N) >= 92L & is.finite(q90_old), by = cluster_id]
  data[, h_exceso := pmin(pmax(mean_ratio_tiempo_periodo_pred - 1, 0), 3)]
  anchor <- data[old_history & is.finite(h_exceso), .(
    valid = all(is.finite(c(mean(mean_tiempo_desde_ultimo_levante_pred, na.rm = TRUE),
      mean(mean_levante_periodo, na.rm = TRUE), mean(mean_ratio_tiempo_periodo_pred, na.rm = TRUE))))) ,
    by = .(dia_objetivo, barrio, segmento)]
  anchor <- anchor[valid == TRUE, .(dia_objetivo, barrio, segmento)]

  # Las cinco ventanas condicionan la cobertura del original; P3 consume solo 7 y 60.
  for (window in c(7L, 15L, 30L, 60L, 90L)) {
    global[, q_global := rf_rolling_aggregate(events, window) / rf_rolling_aggregate(exposure, window)]
    neighborhood[global, on = "dia_objetivo", q_global := i.q_global]
    neighborhood[, q_neighborhood := (rf_rolling_aggregate(events, window) + 200 * q_global) /
      (rf_rolling_aggregate(exposure, window) + 200), by = barrio]
    data[neighborhood, on = c("barrio", "dia_objetivo"), q_neighborhood := i.q_neighborhood]
    data[, (paste0("q_", window)) := (rf_rolling_aggregate(y, window) + 30 * q_neighborhood) /
      (rf_rolling_aggregate(rep(1, .N), window) + 30), by = cluster_id]
  }
  q_columns <- paste0("q_", c(7L, 15L, 30L, 60L, 90L))
  finite_columns <- c(q_columns, "mean_tiempo_desde_ultimo_levante_pred", "mean_levante_periodo",
    "mean_ratio_tiempo_periodo_pred")
  eligible <- data[, Reduce(`&`, lapply(.SD, is.finite)), .SDcols = finite_columns]
  data <- data[eligible & dia_objetivo >= data.table::as.IDate("2025-04-01")]
  p3 <- data[, .(n_clusters = .N, observado = sum(y),
    media_tiempo_levante = mean(mean_tiempo_desde_ultimo_levante_pred),
    rms_q_7 = sqrt(mean(q_7^2)), rms_w_7 = sqrt(mean((q_7 * h_exceso)^2)),
    media_q_7 = mean(q_7), media_q_60 = mean(q_60)), by = .(dia_objetivo, barrio, segmento)]
  p3 <- p3[anchor, on = c("dia_objetivo", "barrio", "segmento"), nomatch = 0]
  p3 <- rf_aggregate_calendar(p3, calendar)[split_modelo != "fuera_split"]
  p3[, `:=`(prop_reclamo = observado / n_clusters, delta_q_7_60 = media_q_7 - media_q_60,
    es_feriado = as.integer(dia_objetivo %in% data.table::as.IDate(holidays)))]
  a0[, version_cluster := spatial_version]
  p3[, version_cluster := spatial_version]
  list(a0_base = a0, p3_base = p3, version_cluster = spatial_version,
    history_semantics = "observaciones_D2_7_60; no calendario ni q30")
}
