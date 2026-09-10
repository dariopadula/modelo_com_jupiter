construir_base_cluster_dia <- function(datos_levante,
                                       asignaciones_com,
                                       contenedor_posicion_cluster,
                                       redondeo_m = 1,
                                       estados_com_validos = c("asignado", "revision"),
                                       estados_cluster_validos = c("referencia", "asignado", "revision"),
                                       limitar_rango_fechas_com = TRUE,
                                       usar_solo_contenedor_dia_elegible_modelo = TRUE) {
  data.table::setDT(datos_levante)
  data.table::setDT(asignaciones_com)
  data.table::setDT(contenedor_posicion_cluster)

  cols_levante <- c(
    "levante_contenedor_id",
    "dia",
    "x",
    "y",
    "contenedor_activo_dia"
  )
  if (!all(cols_levante %in% names(datos_levante))) {
    stop("datos_levante debe tener columnas: ", paste(cols_levante, collapse = ", "))
  }

  cols_com <- c("id", "dia", "cluster_id", "estado_asignacion_com")
  if (!all(cols_com %in% names(asignaciones_com))) {
    stop("asignaciones_com debe tener columnas: ", paste(cols_com, collapse = ", "))
  }

  cols_cluster <- c("levante_contenedor_id", "x", "y", "cluster_id")
  if (!all(cols_cluster %in% names(contenedor_posicion_cluster))) {
    stop("contenedor_posicion_cluster debe tener columnas: ", paste(cols_cluster, collapse = ", "))
  }

  if (!"estado_asignacion_cluster" %in% names(contenedor_posicion_cluster)) {
    contenedor_posicion_cluster[, estado_asignacion_cluster := "referencia"]
  }
  if (!"version_cluster" %in% names(contenedor_posicion_cluster)) {
    contenedor_posicion_cluster[, version_cluster := NA_character_]
  }
  if (!"incidente" %in% names(asignaciones_com)) {
    asignaciones_com[, incidente := NA_character_]
  }

  if (limitar_rango_fechas_com) {
    fecha_min_com <- min(asignaciones_com$dia, na.rm = TRUE)
    fecha_max_com <- max(asignaciones_com$dia, na.rm = TRUE)
    datos_levante <- datos_levante[dia >= fecha_min_com & dia <= fecha_max_com]
  }

  mapa_cluster <- data.table::copy(contenedor_posicion_cluster[
    !is.na(cluster_id) &
      estado_asignacion_cluster %in% estados_cluster_validos &
      !is.na(x) & !is.na(y)
  ])
  mapa_cluster[, `:=`(
    x_redondeado = round(as.numeric(x) / redondeo_m) * redondeo_m,
    y_redondeado = round(as.numeric(y) / redondeo_m) * redondeo_m
  )]
  mapa_cluster <- unique(mapa_cluster[, .(
    levante_contenedor_id,
    x_redondeado,
    y_redondeado,
    cluster_id,
    version_cluster,
    estado_asignacion_cluster
  )])

  conflictos_mapa <- mapa_cluster[
    ,
    .(n_clusters = data.table::uniqueN(cluster_id)),
    by = .(levante_contenedor_id, x_redondeado, y_redondeado)
  ][n_clusters > 1]

  if (nrow(conflictos_mapa) > 0L) {
    stop("Hay posiciones de contenedor con mas de un cluster asignado. Revisar contenedor_posicion_cluster.")
  }

  levante_activo <- data.table::copy(datos_levante[
    contenedor_activo_dia == TRUE & !is.na(dia) & !is.na(x) & !is.na(y)
  ])
  if (!"contenedor_dia_elegible_modelo" %in% names(levante_activo)) {
    levante_activo[, contenedor_dia_elegible_modelo := TRUE]
  }

  levante_elegibilidad_dia <- levante_activo[
    ,
    .(
      n_contenedores_activos_original = data.table::uniqueN(levante_contenedor_id),
      n_contenedores_elegibles_modelo = data.table::uniqueN(levante_contenedor_id[contenedor_dia_elegible_modelo == TRUE])
    ),
    by = dia
  ]

  if (usar_solo_contenedor_dia_elegible_modelo) {
    levante_activo <- levante_activo[contenedor_dia_elegible_modelo == TRUE]
  }

  levante_activo[, `:=`(
    x_redondeado = round(as.numeric(x) / redondeo_m) * redondeo_m,
    y_redondeado = round(as.numeric(y) / redondeo_m) * redondeo_m
  )]

  levante_cluster <- mapa_cluster[
    levante_activo,
    on = .(levante_contenedor_id, x_redondeado, y_redondeado),
    nomatch = 0
  ]

  levante_cluster[, ratio_tiempo_periodo := data.table::fifelse(
    !is.na(tiempo_desde_ant_aj_v2) & !is.na(levante_periodo) & levante_periodo > 0,
    tiempo_desde_ant_aj_v2 / levante_periodo,
    NA_real_
  )]
  if (!"tiempo_desde_ultimo_levante_pred_v2" %in% names(levante_cluster)) {
    levante_cluster[, tiempo_desde_ultimo_levante_pred_v2 := tiempo_desde_ant_aj_v2]
  }
  levante_cluster[, ratio_tiempo_periodo_pred := data.table::fifelse(
    !is.na(tiempo_desde_ultimo_levante_pred_v2) & !is.na(levante_periodo) & levante_periodo > 0,
    tiempo_desde_ultimo_levante_pred_v2 / levante_periodo,
    NA_real_
  )]

  if (nrow(levante_cluster) > 0L) {
    levante_cluster <- levante_cluster[
      ,
      .SD[1],
      by = .(cluster_id, dia, levante_contenedor_id)
    ]
  }

  com_validos <- data.table::copy(asignaciones_com[
    estado_asignacion_com %in% estados_com_validos & !is.na(cluster_id) & !is.na(dia)
  ])

  com_cluster_dia <- com_validos[
    ,
    .(
      n_reclamos = data.table::uniqueN(id),
      n_reclamos_asignado = data.table::uniqueN(id[estado_asignacion_com == "asignado"]),
      n_reclamos_revision = data.table::uniqueN(id[estado_asignacion_com == "revision"]),
      distancia_mediana_m = stats::median(distancia_m, na.rm = TRUE),
      distancia_p90_m = as.numeric(stats::quantile(distancia_m, 0.9, na.rm = TRUE)),
      n_reclamos_desbordado = data.table::uniqueN(id[!is.na(incidente) & incidente == "Contenedor desbordado"]),
      n_reclamos_basura_fuera = data.table::uniqueN(id[!is.na(incidente) & incidente == "Basura fuera del contenedor"]),
      n_reclamos_residuos_esparcidos = data.table::uniqueN(id[!is.na(incidente) & incidente == "Residuos esparcidos"])
    ),
    by = .(cluster_id, dia)
  ]
  com_cluster_dia[, tuvo_reclamo := n_reclamos > 0]

  levante_cluster_dia <- levante_cluster[
    ,
    .(
      version_cluster = version_cluster[which.max(!is.na(version_cluster))],
      n_contenedores_activos = data.table::uniqueN(levante_contenedor_id),
      n_contenedores_elegibles_modelo = data.table::uniqueN(levante_contenedor_id[contenedor_dia_elegible_modelo == TRUE]),
      n_contenedores_observados = data.table::uniqueN(levante_contenedor_id[contenedor_observado_estado_dia == TRUE]),
      n_contenedores_inferidos = data.table::uniqueN(levante_contenedor_id[actividad_observada_o_inferida == "inferida"]),
      n_contenedores_inferencia_lejana = data.table::uniqueN(levante_contenedor_id[actividad_inferida_lejana == TRUE]),
      min_tiempo_desde_ultimo_levante = suppressWarnings(min(tiempo_desde_ant_aj_v2, na.rm = TRUE)),
      mean_tiempo_desde_ultimo_levante = mean(tiempo_desde_ant_aj_v2, na.rm = TRUE),
      median_tiempo_desde_ultimo_levante = stats::median(tiempo_desde_ant_aj_v2, na.rm = TRUE),
      max_tiempo_desde_ultimo_levante = suppressWarnings(max(tiempo_desde_ant_aj_v2, na.rm = TRUE)),
      min_ratio_tiempo_periodo = suppressWarnings(min(ratio_tiempo_periodo, na.rm = TRUE)),
      mean_ratio_tiempo_periodo = mean(ratio_tiempo_periodo, na.rm = TRUE),
      median_ratio_tiempo_periodo = stats::median(ratio_tiempo_periodo, na.rm = TRUE),
      max_ratio_tiempo_periodo = suppressWarnings(max(ratio_tiempo_periodo, na.rm = TRUE)),
      min_tiempo_desde_ultimo_levante_pred = suppressWarnings(min(tiempo_desde_ultimo_levante_pred_v2, na.rm = TRUE)),
      mean_tiempo_desde_ultimo_levante_pred = mean(tiempo_desde_ultimo_levante_pred_v2, na.rm = TRUE),
      median_tiempo_desde_ultimo_levante_pred = stats::median(tiempo_desde_ultimo_levante_pred_v2, na.rm = TRUE),
      max_tiempo_desde_ultimo_levante_pred = suppressWarnings(max(tiempo_desde_ultimo_levante_pred_v2, na.rm = TRUE)),
      min_ratio_tiempo_periodo_pred = suppressWarnings(min(ratio_tiempo_periodo_pred, na.rm = TRUE)),
      mean_ratio_tiempo_periodo_pred = mean(ratio_tiempo_periodo_pred, na.rm = TRUE),
      median_ratio_tiempo_periodo_pred = stats::median(ratio_tiempo_periodo_pred, na.rm = TRUE),
      max_ratio_tiempo_periodo_pred = suppressWarnings(max(ratio_tiempo_periodo_pred, na.rm = TRUE)),
      min_levante_periodo = suppressWarnings(min(levante_periodo, na.rm = TRUE)),
      mean_levante_periodo = mean(levante_periodo, na.rm = TRUE),
      max_levante_periodo = suppressWarnings(max(levante_periodo, na.rm = TRUE)),
      mean_dias_total_tramo_inferido_estado = mean(dias_total_tramo_inferido_estado, na.rm = TRUE),
      max_dias_total_tramo_inferido_estado = suppressWarnings(max(dias_total_tramo_inferido_estado, na.rm = TRUE))
    ),
    by = .(cluster_id, dia)
  ]

  cols_num <- c(
    "min_tiempo_desde_ultimo_levante",
    "mean_tiempo_desde_ultimo_levante",
    "median_tiempo_desde_ultimo_levante",
    "max_tiempo_desde_ultimo_levante",
    "min_ratio_tiempo_periodo",
    "mean_ratio_tiempo_periodo",
    "median_ratio_tiempo_periodo",
    "max_ratio_tiempo_periodo",
    "min_tiempo_desde_ultimo_levante_pred",
    "mean_tiempo_desde_ultimo_levante_pred",
    "median_tiempo_desde_ultimo_levante_pred",
    "max_tiempo_desde_ultimo_levante_pred",
    "min_ratio_tiempo_periodo_pred",
    "mean_ratio_tiempo_periodo_pred",
    "median_ratio_tiempo_periodo_pred",
    "max_ratio_tiempo_periodo_pred",
    "min_levante_periodo",
    "mean_levante_periodo",
    "max_levante_periodo",
    "mean_dias_total_tramo_inferido_estado",
    "max_dias_total_tramo_inferido_estado"
  )
  for (col in cols_num) {
    levante_cluster_dia[is.infinite(get(col)), (col) := NA_real_]
  }

  levante_cluster_dia[, pct_contenedores_inferidos := data.table::fifelse(
    n_contenedores_activos > 0,
    n_contenedores_inferidos / n_contenedores_activos,
    NA_real_
  )]
  levante_cluster_dia[, pct_contenedores_elegibles_modelo := data.table::fifelse(
    n_contenedores_activos > 0,
    n_contenedores_elegibles_modelo / n_contenedores_activos,
    NA_real_
  )]

  base_cluster_dia <- com_cluster_dia[
    levante_cluster_dia,
    on = .(cluster_id, dia)
  ]

  cols_reclamos <- c(
    "n_reclamos",
    "n_reclamos_asignado",
    "n_reclamos_revision",
    "n_reclamos_desbordado",
    "n_reclamos_basura_fuera",
    "n_reclamos_residuos_esparcidos"
  )
  for (col in cols_reclamos) {
    base_cluster_dia[is.na(get(col)), (col) := 0L]
  }
  base_cluster_dia[is.na(tuvo_reclamo), tuvo_reclamo := FALSE]

  base_cluster_dia[, `:=`(
    anio = as.integer(format(dia, "%Y")),
    anio_mes = as.integer(format(dia, "%Y%m"))
  )]
  com_cluster_dia[, `:=`(
    anio = as.integer(format(dia, "%Y")),
    anio_mes = as.integer(format(dia, "%Y%m"))
  )]

  resumen <- data.table::rbindlist(list(
    data.table::data.table(metrica = "filas_base_cluster_dia", valor = nrow(base_cluster_dia)),
    data.table::data.table(metrica = "clusters", valor = data.table::uniqueN(base_cluster_dia$cluster_id)),
    data.table::data.table(metrica = "dias", valor = data.table::uniqueN(base_cluster_dia$dia)),
    data.table::data.table(metrica = "cluster_dia_con_reclamo", valor = sum(base_cluster_dia$tuvo_reclamo)),
    data.table::data.table(metrica = "reclamos_validos_agregados", valor = sum(base_cluster_dia$n_reclamos)),
    data.table::data.table(metrica = "clusters_un_contenedor_dia", valor = base_cluster_dia[n_contenedores_activos == 1L, .N]),
    data.table::data.table(metrica = "clusters_multi_contenedor_dia", valor = base_cluster_dia[n_contenedores_activos > 1L, .N]),
    data.table::data.table(metrica = "contenedores_activos_original_dia_promedio", valor = mean(levante_elegibilidad_dia$n_contenedores_activos_original)),
    data.table::data.table(metrica = "contenedores_elegibles_modelo_dia_promedio", valor = mean(levante_elegibilidad_dia$n_contenedores_elegibles_modelo))
  ))

  list(
    base_cluster_dia = base_cluster_dia,
    com_cluster_dia = com_cluster_dia,
    levante_cluster_dia = levante_cluster_dia,
    resumen = resumen
  )
}
