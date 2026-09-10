asignar_posiciones_levante_a_clusters <- function(datos_levante,
                                                  cluster_members_ref,
                                                  redondeo_m = 1,
                                                  umbral_asignacion_m = 50,
                                                  umbral_revision_m = 100,
                                                  crs = 32721) {
  data.table::setDT(datos_levante)
  data.table::setDT(cluster_members_ref)

  if (!all(c("x", "y") %in% names(datos_levante))) {
    if (all(c("levante_longitud", "levante_latitud") %in% names(datos_levante))) {
      datos_levante[, `:=`(
        x = as.numeric(levante_longitud),
        y = as.numeric(levante_latitud)
      )]
    } else {
      stop("datos_levante debe tener columnas x/y o levante_longitud/levante_latitud")
    }
  }

  cols_ref <- c("version_cluster", "cluster_id", "punto_ref_id", "x", "y")
  if (!all(cols_ref %in% names(cluster_members_ref))) {
    stop("cluster_members_ref debe tener columnas: ", paste(cols_ref, collapse = ", "))
  }

  if (!"levante_contenedor_id" %in% names(datos_levante)) {
    stop("datos_levante debe tener levante_contenedor_id")
  }

  if (!"dia" %in% names(datos_levante)) {
    stop("datos_levante debe tener dia")
  }

  version_ref <- unique(cluster_members_ref$version_cluster)
  if (length(version_ref) != 1) {
    stop("cluster_members_ref debe contener una sola version_cluster")
  }

  datos_validos <- datos_levante[!is.na(x) & !is.na(y)]

  posiciones_actuales <- datos_validos[
    ,
    .(
      fecha_min_observada = min(dia, na.rm = TRUE),
      fecha_max_observada = max(dia, na.rm = TRUE),
      n_observaciones = .N,
      n_contenedores = data.table::uniqueN(levante_contenedor_id)
    ),
    by = .(
      x = round(as.numeric(x) / redondeo_m) * redondeo_m,
      y = round(as.numeric(y) / redondeo_m) * redondeo_m
    )
  ]

  contenedor_posicion_actual <- unique(datos_validos[
    ,
    .(
      levante_contenedor_id,
      x = round(as.numeric(x) / redondeo_m) * redondeo_m,
      y = round(as.numeric(y) / redondeo_m) * redondeo_m,
      levante_circuito = if ("levante_circuito" %in% names(datos_validos)) levante_circuito else NA_character_,
      levante_posicion_en_circuito = if ("levante_posicion_en_circuito" %in% names(datos_validos)) levante_posicion_en_circuito else NA_real_
    )
  ])

  ref_xy <- unique(cluster_members_ref[, .(x, y, cluster_id, punto_ref_id)])

  posiciones_conocidas <- ref_xy[
    posiciones_actuales,
    on = .(x, y),
    nomatch = 0
  ][
    ,
    `:=`(
      version_cluster = version_ref,
      estado_asignacion = "referencia",
      cluster_id_asignado = cluster_id,
      cluster_id_candidato = cluster_id,
      punto_ref_id_mas_cercano = punto_ref_id,
      distancia_m = 0
    )
  ]

  posiciones_nuevas <- posiciones_actuales[
    !ref_xy,
    on = .(x, y)
  ][
    ,
    punto_nuevo_id := paste0("PN", sprintf("%07d", .I))
  ]

  if (nrow(posiciones_nuevas) > 0) {
    posiciones_nuevas_asignadas <- asignar_puntos_a_clusters_referencia(
      puntos_nuevos = posiciones_nuevas[, .(punto_nuevo_id, x, y)],
      cluster_members_ref = cluster_members_ref,
      umbral_asignacion_m = umbral_asignacion_m,
      umbral_revision_m = umbral_revision_m,
      crs = crs
    )

    posiciones_nuevas_asignadas <- posiciones_nuevas[
      posiciones_nuevas_asignadas,
      on = .(punto_nuevo_id, x, y)
    ]
  } else {
    posiciones_nuevas_asignadas <- data.table::data.table(
      punto_nuevo_id = character(),
      x = numeric(),
      y = numeric(),
      fecha_min_observada = as.IDate(character()),
      fecha_max_observada = as.IDate(character()),
      n_observaciones = integer(),
      n_contenedores = integer(),
      version_cluster = character(),
      cluster_id_candidato = character(),
      punto_ref_id_mas_cercano = character(),
      distancia_m = numeric(),
      estado_asignacion = character(),
      cluster_id_asignado = character(),
      umbral_asignacion_m = numeric(),
      umbral_revision_m = numeric(),
      crs = numeric(),
      fecha_asignacion = as.Date(character())
    )
  }

  posiciones_conocidas_norm <- posiciones_conocidas[
    ,
    .(
      x,
      y,
      fecha_min_observada,
      fecha_max_observada,
      n_observaciones,
      n_contenedores,
      version_cluster,
      cluster_id_candidato,
      punto_ref_id_mas_cercano,
      distancia_m,
      estado_asignacion,
      cluster_id_asignado
    )
  ]

  posiciones_nuevas_norm <- posiciones_nuevas_asignadas[
    ,
    .(
      x,
      y,
      fecha_min_observada,
      fecha_max_observada,
      n_observaciones,
      n_contenedores,
      version_cluster,
      cluster_id_candidato,
      punto_ref_id_mas_cercano,
      distancia_m,
      estado_asignacion,
      cluster_id_asignado
    )
  ]

  posiciones_cluster_actual <- data.table::rbindlist(
    list(posiciones_conocidas_norm, posiciones_nuevas_norm),
    fill = TRUE
  )

  contenedor_posicion_cluster_actual <- posiciones_cluster_actual[
    contenedor_posicion_actual,
    on = .(x, y)
  ][
    ,
    .(
      version_cluster,
      levante_contenedor_id,
      x,
      y,
      cluster_id = cluster_id_asignado,
      estado_asignacion_cluster = estado_asignacion,
      cluster_id_candidato,
      punto_ref_id_mas_cercano,
      distancia_m,
      levante_circuito,
      levante_posicion_en_circuito
    )
  ]

  resumen_asignacion <- data.table::rbindlist(list(
    data.table::data.table(
      metrica = "posiciones_referencia",
      valor = nrow(ref_xy)
    ),
    data.table::data.table(
      metrica = "posiciones_actuales",
      valor = nrow(posiciones_actuales)
    ),
    data.table::data.table(
      metrica = "posiciones_conocidas",
      valor = nrow(posiciones_conocidas)
    ),
    data.table::data.table(
      metrica = "posiciones_nuevas",
      valor = nrow(posiciones_nuevas)
    ),
    posiciones_cluster_actual[
      ,
      .(metrica = paste0("estado_", estado_asignacion), valor = .N),
      by = estado_asignacion
    ][, estado_asignacion := NULL]
  ), fill = TRUE)

  list(
    posiciones_actuales = posiciones_actuales,
    posiciones_conocidas = posiciones_conocidas,
    posiciones_nuevas = posiciones_nuevas,
    posiciones_nuevas_asignadas = posiciones_nuevas_asignadas,
    posiciones_cluster_actual = posiciones_cluster_actual,
    contenedor_posicion_cluster_actual = contenedor_posicion_cluster_actual,
    resumen_asignacion = resumen_asignacion
  )
}
