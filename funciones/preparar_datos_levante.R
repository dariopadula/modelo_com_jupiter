preparar_datos_levante <- function(datos,
                                   anio_mes_objetivo = NULL,
                                   fecha_min = NULL,
                                   fecha_max = NULL,
                                   umbral_gap_actividad_dias = 8,
                                   umbral_gap_actividad_max_dias = 30,
                                   umbral_inferencia_lejana_dias = umbral_gap_actividad_dias,
                                   max_dias_total_tramo_inferido_elegible = 15,
                                   hora_corte_prediccion = 1,
                                   multiplicador_periodo_gap = 4,
                                   usar_levante_activo = TRUE) {
  data.table::setDT(datos)

  datos <- datos[nchar(levante_contenedor_id) >= 5]

  if (!"levante_activo" %in% names(datos)) {
    datos[, levante_activo := NA_integer_]
  }

  cols_opcionales <- c(
    "levante_motivo_no_levante_id",
    "levante_motivo_no_levante_descripcion"
  )
  for (col in cols_opcionales) {
    if (!col %in% names(datos)) datos[, (col) := NA]
  }

  datos[, `:=`(
    fecha_levante = as.POSIXct(levante_fecha_levante, format = "%Y-%m-%d %H:%M:%OS"),
    fecha_fact = as.POSIXct(levante_fact, format = "%Y-%m-%d %H:%M:%OS"),
    levante_periodo = as.numeric(levante_periodo),
    levante_activo = as.integer(levante_activo)
  )]

  datos[, `:=`(
    fecha = fecha_levante,
    dia_levante = as.IDate(fecha_levante),
    dia_fact = as.IDate(fecha_fact)
  )]

  eventos_estado <- data.table::copy(datos[!is.na(fecha_fact)])
  if (nrow(eventos_estado) == 0L) {
    return(data.table::data.table())
  }

  if (is.null(fecha_min)) fecha_min <- min(eventos_estado$dia_fact, na.rm = TRUE)
  if (is.null(fecha_max)) fecha_max <- max(eventos_estado$dia_fact, na.rm = TRUE)

  intervalos_actividad <- definir_intervalos_actividad_contenedor(
    eventos_estado,
    fecha_min = fecha_min,
    fecha_max = fecha_max,
    umbral_gap_dias = umbral_gap_actividad_dias,
    umbral_gap_max_dias = umbral_gap_actividad_max_dias,
    multiplicador_periodo_gap = multiplicador_periodo_gap,
    usar_levante_activo = usar_levante_activo
  )

  if (nrow(intervalos_actividad) == 0L) {
    return(data.table::data.table())
  }

  grilla <- intervalos_actividad[
    ,
    .(dia = seq(fecha_inicio_activo, fecha_fin_activo, by = "day")),
    by = .(
      levante_contenedor_id,
      intervalo_actividad_id,
      fecha_inicio_activo,
      fecha_fin_activo,
      fecha_fin_observada,
      motivo_inicio_actividad,
      motivo_fin_actividad,
      gap_previo_dias,
      gap_siguiente_dias,
      umbral_gap_dias_usado,
      n_dias_observados_intervalo,
      n_eventos_estado_intervalo
    )
  ]

  cols_atributos <- c(
    "levante_periodo",
    "levante_longitud",
    "levante_latitud",
    "levante_circuito",
    "levante_posicion_en_circuito",
    "levante_motivo_no_levante_id",
    "levante_motivo_no_levante_descripcion"
  )

  setorder(eventos_estado, levante_contenedor_id, dia_fact, fecha_fact, fecha_levante)
  estado_dia <- eventos_estado[
    ,
    .SD[.N],
    by = .(levante_contenedor_id, dia_fact),
    .SDcols = c("fecha_fact", "levante_activo", cols_atributos)
  ]
  data.table::setnames(estado_dia, "dia_fact", "dia")
  estado_dia[, `:=`(
    estado_activo_obs = levante_activo,
    contenedor_observado_estado_dia = TRUE
  )]
  estado_dia[, levante_activo := NULL]

  levantes <- data.table::copy(datos[!is.na(fecha_levante)])
  if (nrow(levantes) > 0L) {
    setorder(levantes, levante_contenedor_id, fecha_levante, fecha_fact)

    levantes[, `:=`(
      id_ant = data.table::shift(levante_contenedor_id),
      fecha_levante_ant = data.table::shift(fecha_levante)
    )]

    levantes[, tiempo_desde_ant := data.table::fifelse(
      levante_contenedor_id == id_ant,
      as.numeric(difftime(fecha_levante, fecha_levante_ant, units = "days")),
      NA_real_
    )]

    levantes_dia <- levantes[
      order(-tiempo_desde_ant)
    ][
      ,
      .SD[1],
      by = .(levante_contenedor_id, dia_levante)
    ]

    levantes_dia <- levantes_dia[
      ,
      .(
        levante_contenedor_id,
        dia = dia_levante,
        fecha_levante,
        fecha_fact_levante = fecha_fact,
        tiempo_desde_ant,
        contenedor_observado_levante_dia = TRUE
      )
    ]
  } else {
    levantes_dia <- data.table::data.table(
      levante_contenedor_id = character(),
      dia = as.IDate(character()),
      fecha_levante = as.POSIXct(character()),
      fecha_fact_levante = as.POSIXct(character()),
      tiempo_desde_ant = numeric(),
      contenedor_observado_levante_dia = logical()
    )
  }

  datos <- estado_dia[grilla, on = .(levante_contenedor_id, dia)]
  datos <- levantes_dia[datos, on = .(levante_contenedor_id, dia)]

  setorder(datos, levante_contenedor_id, intervalo_actividad_id, dia)

  datos[is.na(contenedor_observado_estado_dia), contenedor_observado_estado_dia := FALSE]
  datos[is.na(contenedor_observado_levante_dia), contenedor_observado_levante_dia := FALSE]
  datos[, contenedor_observado_dia := contenedor_observado_estado_dia]

  datos[
    contenedor_observado_estado_dia == TRUE,
    fecha_ultima_observacion_estado := dia
  ]
  datos[
    contenedor_observado_estado_dia == TRUE,
    fecha_siguiente_observacion_estado := dia
  ]
  datos[
    ,
    fecha_ultima_observacion_estado := zoo::na.locf(fecha_ultima_observacion_estado, na.rm = FALSE),
    by = .(levante_contenedor_id, intervalo_actividad_id)
  ]
  datos[
    ,
    fecha_siguiente_observacion_estado := zoo::na.locf(fecha_siguiente_observacion_estado, na.rm = FALSE, fromLast = TRUE),
    by = levante_contenedor_id
  ]
  datos[, dias_desde_ultima_observacion_estado := as.numeric(dia - fecha_ultima_observacion_estado)]
  datos[, dias_hasta_siguiente_observacion_estado := as.numeric(fecha_siguiente_observacion_estado - dia)]
  datos[, actividad_observada_o_inferida := data.table::fifelse(
    contenedor_observado_estado_dia,
    "observada",
    "inferida"
  )]
  datos[, dias_total_tramo_inferido_estado := data.table::fifelse(
    actividad_observada_o_inferida == "observada",
    0,
    data.table::fifelse(
      !is.na(fecha_siguiente_observacion_estado),
      pmax(as.numeric(fecha_siguiente_observacion_estado - fecha_ultima_observacion_estado) - 1, 0),
      as.numeric(fecha_fin_activo - fecha_ultima_observacion_estado)
    )
  )]
  datos[, actividad_inferida_lejana := actividad_observada_o_inferida == "inferida" &
    !is.na(dias_desde_ultima_observacion_estado) &
    dias_desde_ultima_observacion_estado > umbral_inferencia_lejana_dias]

  datos[
    ,
    (cols_atributos) := lapply(.SD, zoo::na.locf, na.rm = FALSE),
    by = levante_contenedor_id,
    .SDcols = cols_atributos
  ]

  datos[
    ,
    (cols_atributos) := lapply(.SD, zoo::na.locf, na.rm = FALSE, fromLast = TRUE),
    by = levante_contenedor_id,
    .SDcols = cols_atributos
  ]

  datos[
    ,
    estado_activo_prop := zoo::na.locf(estado_activo_obs, na.rm = FALSE),
    by = .(levante_contenedor_id, intervalo_actividad_id)
  ]

  datos[is.na(estado_activo_prop), estado_activo_prop := 1L]
  datos[, contenedor_activo_dia := estado_activo_prop == 1L]
  datos[, contenedor_dia_elegible_modelo := contenedor_activo_dia == TRUE & (
    actividad_observada_o_inferida == "observada" |
      (
        actividad_observada_o_inferida == "inferida" &
          !is.na(dias_desde_ultima_observacion_estado) &
          !is.na(dias_total_tramo_inferido_estado) &
          dias_desde_ultima_observacion_estado <= umbral_inferencia_lejana_dias &
          dias_total_tramo_inferido_estado <= max_dias_total_tramo_inferido_elegible
      )
  )]

  datos[
    ,
    fecha_ultimo_levante := zoo::na.locf(fecha_levante, na.rm = FALSE),
    by = .(levante_contenedor_id, intervalo_actividad_id)
  ]

  datos[
    ,
    horas_desde_ultimo_levante := as.numeric(
      difftime(as.POSIXct(dia) + lubridate::hours(24), fecha_ultimo_levante, units = "hours")
    )
  ]

  datos[, `:=`(
    x = as.numeric(levante_longitud),
    y = as.numeric(levante_latitud)
  )]

  datos[, tiempo_desde_ant_aj := horas_desde_ultimo_levante / 24]
  datos[, tiempo_desde_ant_aj_v2 := data.table::fifelse(
    contenedor_activo_dia,
    tiempo_desde_ant_aj,
    NA_real_
  )]

  datos[, fecha_corte_prediccion := as.POSIXct(dia) + lubridate::hours(hora_corte_prediccion)]

  if (nrow(levantes) > 0L) {
    levantes_pred <- unique(levantes[
      !is.na(fecha_levante),
      .(
        levante_contenedor_id,
        fecha_ultimo_levante_pred = fecha_levante
      )
    ])
    levantes_pred[, fecha_corte_prediccion := fecha_ultimo_levante_pred]

    datos[, fila_pred := .I]
    consulta_pred <- datos[
      ,
      .(fila_pred, levante_contenedor_id, fecha_corte_prediccion)
    ]

    data.table::setkey(levantes_pred, levante_contenedor_id, fecha_corte_prediccion)
    data.table::setkey(consulta_pred, levante_contenedor_id, fecha_corte_prediccion)

    ultimo_pred <- levantes_pred[
      consulta_pred,
      roll = Inf
    ][
      ,
      .(fila_pred, fecha_ultimo_levante_pred)
    ]

    datos[
      ultimo_pred,
      fecha_ultimo_levante_pred := i.fecha_ultimo_levante_pred,
      on = "fila_pred"
    ]
    datos[, fila_pred := NULL]

    datos[
      !is.na(fecha_ultimo_levante_pred) &
        fecha_ultimo_levante_pred < as.POSIXct(fecha_inicio_activo),
      fecha_ultimo_levante_pred := as.POSIXct(NA)
    ]
  } else {
    datos[, fecha_ultimo_levante_pred := as.POSIXct(NA)]
  }

  datos[
    ,
    horas_desde_ultimo_levante_pred := as.numeric(
      difftime(fecha_corte_prediccion, fecha_ultimo_levante_pred, units = "hours")
    )
  ]
  datos[, tiempo_desde_ultimo_levante_pred := horas_desde_ultimo_levante_pred / 24]
  datos[, tiempo_desde_ultimo_levante_pred_v2 := data.table::fifelse(
    contenedor_activo_dia,
    tiempo_desde_ultimo_levante_pred,
    NA_real_
  )]

  datos[, anio := as.integer(format(dia, "%Y"))]
  datos[, anio_mes := as.integer(format(dia, "%Y%m"))]

  if (!is.null(anio_mes_objetivo)) {
    datos <- datos[anio_mes %in% anio_mes_objetivo]
  }

  datos[]
}
