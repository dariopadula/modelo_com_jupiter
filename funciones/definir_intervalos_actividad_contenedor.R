definir_intervalos_actividad_contenedor <- function(datos_eventos,
                                                    fecha_min = NULL,
                                                    fecha_max = NULL,
                                                    umbral_gap_dias = 8,
                                                    umbral_gap_max_dias = 30,
                                                    multiplicador_periodo_gap = 4,
                                                    usar_levante_activo = TRUE) {
  data.table::setDT(datos_eventos)

  eventos <- data.table::copy(datos_eventos[!is.na(fecha_fact)])

  if (nrow(eventos) == 0L) {
    return(data.table::data.table(
      levante_contenedor_id = character(),
      intervalo_actividad_id = character(),
      fecha_inicio_activo = as.IDate(character()),
      fecha_fin_activo = as.IDate(character()),
      motivo_inicio_actividad = character(),
      motivo_fin_actividad = character(),
      gap_previo_dias = numeric(),
      gap_siguiente_dias = numeric(),
      umbral_gap_dias_usado = numeric()
    ))
  }

  if (!"dia_fact" %in% names(eventos)) {
    eventos[, dia_fact := as.IDate(fecha_fact)]
  }
  if (!"fecha_levante" %in% names(eventos)) {
    eventos[, fecha_levante := as.POSIXct(NA)]
  }

  if (is.null(fecha_min)) fecha_min <- min(eventos$dia_fact, na.rm = TRUE)
  if (is.null(fecha_max)) fecha_max <- max(eventos$dia_fact, na.rm = TRUE)
  fecha_min <- as.IDate(fecha_min)
  fecha_max <- as.IDate(fecha_max)

  if (!"levante_activo" %in% names(eventos)) {
    eventos[, levante_activo := NA_integer_]
  }

  eventos[, estado_activo_obs := suppressWarnings(as.integer(levante_activo))]
  if (!usar_levante_activo || all(is.na(eventos$estado_activo_obs))) {
    eventos[, estado_activo_obs := 1L]
  } else {
    eventos[is.na(estado_activo_obs), estado_activo_obs := 1L]
  }

  if (!"levante_periodo" %in% names(eventos)) {
    eventos[, levante_periodo := NA_real_]
  }
  eventos[, levante_periodo := suppressWarnings(as.numeric(levante_periodo))]

  setorder(eventos, levante_contenedor_id, dia_fact, fecha_fact, fecha_levante)

  eventos[, `:=`(
    fila_evento = seq_len(.N),
    dia_anterior = data.table::shift(dia_fact),
    estado_anterior = data.table::shift(estado_activo_obs),
    periodo_anterior = data.table::shift(levante_periodo)
  ), by = levante_contenedor_id]

  eventos[, gap_previo_dias := as.numeric(dia_fact - dia_anterior)]
  eventos[, periodo_ref_gap := data.table::fcoalesce(levante_periodo, periodo_anterior)]
  eventos[, umbral_gap_dias_usado := pmax(
    umbral_gap_dias,
    multiplicador_periodo_gap * periodo_ref_gap,
    na.rm = TRUE
  )]
  eventos[is.infinite(umbral_gap_dias_usado), umbral_gap_dias_usado := umbral_gap_dias]
  if (!is.null(umbral_gap_max_dias) && is.finite(umbral_gap_max_dias)) {
    eventos[, umbral_gap_dias_usado := pmin(umbral_gap_dias_usado, umbral_gap_max_dias)]
  }

  eventos[, corta_intervalo := data.table::fifelse(
    is.na(dia_anterior) |
      estado_activo_obs != 1L |
      estado_anterior != 1L |
      (!is.na(gap_previo_dias) & gap_previo_dias > umbral_gap_dias_usado),
    TRUE,
    FALSE
  )]

  eventos[, intervalo_num := cumsum(corta_intervalo), by = levante_contenedor_id]

  eventos_activos <- eventos[estado_activo_obs == 1L]
  if (nrow(eventos_activos) == 0L) {
    return(data.table::data.table(
      levante_contenedor_id = character(),
      intervalo_actividad_id = character(),
      fecha_inicio_activo = as.IDate(character()),
      fecha_fin_activo = as.IDate(character()),
      motivo_inicio_actividad = character(),
      motivo_fin_actividad = character(),
      gap_previo_dias = numeric(),
      gap_siguiente_dias = numeric(),
      umbral_gap_dias_usado = numeric()
    ))
  }

  intervalos <- eventos_activos[
    ,
    .(
      fecha_inicio_activo = min(dia_fact),
      fecha_fin_observada = max(dia_fact),
      fila_evento_fin = max(fila_evento),
      gap_previo_dias = gap_previo_dias[1],
      umbral_gap_dias_usado = umbral_gap_dias_usado[.N],
      n_dias_observados_intervalo = data.table::uniqueN(dia_fact),
      n_eventos_estado_intervalo = .N
    ),
    by = .(levante_contenedor_id, intervalo_num)
  ]

  setorder(intervalos, levante_contenedor_id, fecha_inicio_activo)
  intervalos[, intervalo_actividad_n := seq_len(.N), by = levante_contenedor_id]

  eventos_siguientes <- eventos[
    ,
    .(
      levante_contenedor_id,
      fila_evento_siguiente = fila_evento,
      fecha_siguiente_evento = dia_fact,
      estado_siguiente_evento = estado_activo_obs
    )
  ]

  intervalos[, fila_evento_siguiente := fila_evento_fin + 1L]
  intervalos <- eventos_siguientes[
    intervalos,
    on = .(levante_contenedor_id, fila_evento_siguiente)
  ]

  intervalos[, gap_siguiente_dias := as.numeric(fecha_siguiente_evento - fecha_fin_observada)]
  intervalos[, fecha_fin_maxima_por_umbral := fecha_fin_observada + ceiling(umbral_gap_dias_usado)]
  intervalos[, fecha_fin_limite_siguiente := data.table::fifelse(
    !is.na(fecha_siguiente_evento),
    fecha_siguiente_evento - 1L,
    fecha_max,
    fecha_fin_observada
  )]
  
  intervalos[, fecha_fin_activo := pmin(
    fecha_fin_maxima_por_umbral,
    fecha_fin_limite_siguiente,
    fecha_max,
    na.rm = TRUE
  )]

  intervalos[fecha_inicio_activo < fecha_min, fecha_inicio_activo := fecha_min]
  intervalos[fecha_fin_activo > fecha_max, fecha_fin_activo := fecha_max]
  intervalos <- intervalos[fecha_inicio_activo <= fecha_fin_activo]

  intervalos[, motivo_inicio_actividad := data.table::fifelse(
    intervalo_actividad_n == 1L,
    "primer_activo_observado",
    data.table::fifelse(
      !is.na(gap_previo_dias) & gap_previo_dias > umbral_gap_dias_usado,
      "reintegracion_gap_largo",
      "reintegracion_estado_activo"
    )
  )]

  intervalos[, motivo_fin_actividad := data.table::fifelse(
    !is.na(fecha_siguiente_evento) & estado_siguiente_evento != 1L,
    "cierre_por_estado_inactivo",
    data.table::fifelse(
      !is.na(fecha_siguiente_evento) & estado_siguiente_evento == 1L,
      "cierre_por_gap_largo",
      data.table::fifelse(
        fecha_fin_activo < fecha_max,
        "cierre_por_umbral_sin_observacion",
        "censura_derecha"
      )
    )
  )]

  intervalos[, intervalo_actividad_id := paste(
    levante_contenedor_id,
    sprintf("%03d", intervalo_actividad_n),
    sep = "_"
  )]

  intervalos[
    ,
    .(
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
}
