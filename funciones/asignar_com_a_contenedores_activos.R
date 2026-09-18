asignar_com_a_contenedores_activos <- function(datos_com,
                                               datos_levante,
                                               contenedor_posicion_cluster,
                                               redondeo_m = 1,
                                               umbral_asignacion_m = 50,
                                               umbral_revision_m = 100,
                                               excluir_actividad_inferida_lejana = FALSE,
                                               max_dias_total_tramo_inferido_estado = NULL,
                                               usar_solo_contenedor_dia_elegible_modelo = TRUE,
                                               estados_cluster_validos = c("referencia", "asignado", "revision"),
                                               crs = 32721) {
  data.table::setDT(datos_com)
  data.table::setDT(datos_levante)
  data.table::setDT(contenedor_posicion_cluster)

  cols_com <- c("id", "dia", "x", "y")
  if (!all(cols_com %in% names(datos_com))) {
    stop("datos_com debe tener columnas: ", paste(cols_com, collapse = ", "))
  }
  if (!"incidente" %in% names(datos_com)) {
    datos_com[, incidente := NA_character_]
  }

  cols_levante <- c("levante_contenedor_id", "dia", "x", "y", "contenedor_activo_dia")
  if (!all(cols_levante %in% names(datos_levante))) {
    stop("datos_levante debe tener columnas: ", paste(cols_levante, collapse = ", "))
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

  com_validos <- data.table::copy(datos_com[!is.na(id) & !is.na(dia) & !is.na(x) & !is.na(y)])
  com_sin_coord <- data.table::copy(datos_com[is.na(id) | is.na(dia) | is.na(x) | is.na(y)])

  if (nrow(com_validos) == 0L) {
    asignaciones <- datos_com[, .(
      id,
      dia,
      x_com = x,
      y_com = y,
      levante_contenedor_id = NA_character_,
      cluster_id = NA_character_,
      estado_asignacion_com = "sin_coordenadas_com",
      distancia_m = NA_real_
    )]

    return(list(
      asignaciones_com = asignaciones,
      resumen_asignacion = asignaciones[, .N, by = estado_asignacion_com],
      candidatos_activos_cluster = data.table::data.table()
    ))
  }

  levante_candidatos <- data.table::copy(datos_levante[
    contenedor_activo_dia == TRUE & !is.na(dia) & !is.na(x) & !is.na(y)
  ])

  if (usar_solo_contenedor_dia_elegible_modelo &&
      "contenedor_dia_elegible_modelo" %in% names(levante_candidatos)) {
    levante_candidatos <- levante_candidatos[contenedor_dia_elegible_modelo == TRUE]
  }

  if (excluir_actividad_inferida_lejana && "actividad_inferida_lejana" %in% names(levante_candidatos)) {
    levante_candidatos <- levante_candidatos[actividad_inferida_lejana == FALSE | is.na(actividad_inferida_lejana)]
  }

  if (!is.null(max_dias_total_tramo_inferido_estado) &&
      "dias_total_tramo_inferido_estado" %in% names(levante_candidatos)) {
    levante_candidatos <- levante_candidatos[
      is.na(dias_total_tramo_inferido_estado) |
        dias_total_tramo_inferido_estado <= max_dias_total_tramo_inferido_estado |
        actividad_observada_o_inferida == "observada"
    ]
  }

  levante_candidatos[, `:=`(
    x_redondeado = round(as.numeric(x) / redondeo_m) * redondeo_m,
    y_redondeado = round(as.numeric(y) / redondeo_m) * redondeo_m
  )]

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
    estado_asignacion_cluster,
    distancia_posicion_cluster_m = if ("distancia_m" %in% names(mapa_cluster)) distancia_m else NA_real_
  )])

  conflictos_mapa <- mapa_cluster[
    ,
    .(n_clusters = data.table::uniqueN(cluster_id)),
    by = .(levante_contenedor_id, x_redondeado, y_redondeado)
  ][n_clusters > 1]

  if (nrow(conflictos_mapa) > 0L) {
    stop("Hay posiciones de contenedor con mas de un cluster asignado. Revisar contenedor_posicion_cluster.")
  }

  candidatos <- mapa_cluster[
    levante_candidatos,
    on = .(levante_contenedor_id, x_redondeado, y_redondeado),
    nomatch = 0
  ]

  if (nrow(candidatos) > 0L) {
    candidatos <- candidatos[
      ,
      .SD[1],
      by = .(dia, levante_contenedor_id, x_redondeado, y_redondeado)
    ]
  }

  dias_com <- sort(unique(com_validos$dia))
  asignaciones_validas <- data.table::rbindlist(lapply(dias_com, function(dia_i) {
    com_dia <- com_validos[dia == dia_i]
    cand_dia <- candidatos[dia == dia_i]

    if (nrow(cand_dia) == 0L) {
      return(com_dia[, .(
        id,
        dia,
        incidente,
        x_com = x,
        y_com = y,
        levante_contenedor_id = NA_character_,
        cluster_id = NA_character_,
        version_cluster = NA_character_,
        estado_asignacion_cluster = NA_character_,
        distancia_posicion_cluster_m = NA_real_,
        x_contenedor = NA_real_,
        y_contenedor = NA_real_,
        distancia_m = NA_real_,
        estado_asignacion_com = "sin_candidatos_activos",
        n_candidatos_dia = 0L,
        actividad_observada_o_inferida = NA_character_,
        actividad_inferida_lejana = NA,
        dias_desde_ultima_observacion_estado = NA_real_,
        dias_total_tramo_inferido_estado = NA_real_,
        contenedor_dia_elegible_modelo = NA,
        tiempo_desde_ant_aj_v2 = NA_real_
      )])
    }

    cand_pos <- unique(cand_dia[
      ,
      .(
        levante_contenedor_id,
        cluster_id,
        version_cluster,
        estado_asignacion_cluster,
        distancia_posicion_cluster_m,
        x_contenedor = x,
        y_contenedor = y,
        actividad_observada_o_inferida,
        actividad_inferida_lejana,
        dias_desde_ultima_observacion_estado,
        dias_total_tramo_inferido_estado,
        contenedor_dia_elegible_modelo = if ("contenedor_dia_elegible_modelo" %in% names(cand_dia)) contenedor_dia_elegible_modelo else NA,
        tiempo_desde_ant_aj_v2
      )
    ])

    nn <- vecinos_cercanos(
      data = as.matrix(cand_pos[, .(x_contenedor, y_contenedor)]),
      query = as.matrix(com_dia[, .(x, y)]),
      k = 1
    )

    idx <- nn$nn.index[, 1]
    dist <- nn$nn.dist[, 1]

    res <- data.table::data.table(
      id = com_dia$id,
      dia = com_dia$dia,
      incidente = com_dia$incidente,
      x_com = com_dia$x,
      y_com = com_dia$y,
      cand_pos[idx],
      distancia_m = dist,
      estado_asignacion_com = data.table::fcase(
        dist <= umbral_asignacion_m, "asignado",
        dist <= umbral_revision_m, "revision",
        default = "pendiente"
      ),
      n_candidatos_dia = nrow(cand_pos)
    )

    res[, cluster_id := data.table::fifelse(
      estado_asignacion_com %in% c("asignado", "revision"),
      cluster_id,
      NA_character_
    )]

    res[]
  }), fill = TRUE)

  asignaciones_sin_coord <- data.table::data.table()
  if (nrow(com_sin_coord) > 0L) {
    asignaciones_sin_coord <- com_sin_coord[, .(
      id,
      dia,
      incidente,
      x_com = x,
      y_com = y,
      levante_contenedor_id = NA_character_,
      cluster_id = NA_character_,
      version_cluster = NA_character_,
      estado_asignacion_cluster = NA_character_,
      distancia_posicion_cluster_m = NA_real_,
      x_contenedor = NA_real_,
      y_contenedor = NA_real_,
      distancia_m = NA_real_,
      estado_asignacion_com = "sin_coordenadas_com",
      n_candidatos_dia = NA_integer_,
      actividad_observada_o_inferida = NA_character_,
      actividad_inferida_lejana = NA,
      dias_desde_ultima_observacion_estado = NA_real_,
      dias_total_tramo_inferido_estado = NA_real_,
      contenedor_dia_elegible_modelo = NA,
      tiempo_desde_ant_aj_v2 = NA_real_
    )]
  }

  asignaciones_com <- data.table::rbindlist(
    list(asignaciones_validas, asignaciones_sin_coord),
    fill = TRUE
  )

  resumen_asignacion <- data.table::rbindlist(list(
    data.table::data.table(
      metrica = "reclamos_com",
      valor = nrow(datos_com)
    ),
    data.table::data.table(
      metrica = "reclamos_com_validos_coord",
      valor = nrow(com_validos)
    ),
    data.table::data.table(
      metrica = "candidatos_con_cluster_dia",
      valor = nrow(candidatos)
    ),
    asignaciones_com[
      ,
      .(metrica = paste0("estado_com_", estado_asignacion_com), valor = .N),
      by = estado_asignacion_com
    ][, estado_asignacion_com := NULL],
    asignaciones_com[
      !is.na(distancia_m),
      .(
        metrica = c("distancia_mediana_m", "distancia_p90_m", "distancia_max_m"),
        valor = c(
          stats::median(distancia_m),
          as.numeric(stats::quantile(distancia_m, 0.9)),
          max(distancia_m)
        )
      )
    ]
  ), fill = TRUE)

  resumen_por_dia <- asignaciones_com[
    ,
    .(
      n_com = .N,
      n_asignado = sum(estado_asignacion_com == "asignado"),
      n_revision = sum(estado_asignacion_com == "revision"),
      n_pendiente = sum(estado_asignacion_com == "pendiente"),
      distancia_mediana_m = stats::median(distancia_m, na.rm = TRUE),
      distancia_p90_m = as.numeric(stats::quantile(distancia_m, 0.9, na.rm = TRUE))
    ),
    by = dia
  ][order(dia)]

  asignaciones_com[, `:=`(
    umbral_asignacion_m = umbral_asignacion_m,
    umbral_revision_m = umbral_revision_m,
    crs = crs
  )]

  list(
    asignaciones_com = asignaciones_com,
    resumen_asignacion = resumen_asignacion,
    resumen_por_dia = resumen_por_dia,
    candidatos_activos_cluster = candidatos
  )
}
