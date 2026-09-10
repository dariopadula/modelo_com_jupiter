entrenar_clusters_referencia <- function(datos_levante,
                                         eps_m = 50,
                                         min_pts = 2,
                                         version_cluster = paste0("v", format(Sys.Date(), "%Y_%m_%d")),
                                         crs = 32721,
                                         redondeo_m = 1) {
  if (!requireNamespace("dbscan", quietly = TRUE)) {
    stop("El paquete dbscan es necesario para entrenar clusters de referencia")
  }

  data.table::setDT(datos_levante)

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

  if (!"levante_contenedor_id" %in% names(datos_levante)) {
    stop("datos_levante debe tener la columna levante_contenedor_id")
  }

  if (!"dia" %in% names(datos_levante)) {
    stop("datos_levante debe tener la columna dia")
  }

  datos_levante <- datos_levante[!is.na(x) & !is.na(y)]

  posiciones <- datos_levante[
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

  data.table::setorder(posiciones, x, y)
  posiciones[, punto_ref_id := paste0("P", sprintf("%07d", .I))]

  fit <- dbscan::dbscan(
    as.matrix(posiciones[, .(x, y)]),
    eps = eps_m,
    minPts = min_pts
  )

  posiciones[, cluster_dbscan := fit$cluster]

  clusters_dbscan <- posiciones[
    cluster_dbscan > 0,
    .(
      x_orden = min(x),
      y_orden = min(y),
      n_puntos = .N
    ),
    by = cluster_dbscan
  ]

  data.table::setorder(clusters_dbscan, x_orden, y_orden, cluster_dbscan)
  clusters_dbscan[, cluster_id := paste0("CL", sprintf("%06d", .I))]

  posiciones <- clusters_dbscan[
    posiciones,
    on = "cluster_dbscan"
  ]

  n_clusters_dbscan <- nrow(clusters_dbscan)

  posiciones[
    cluster_dbscan == 0,
    cluster_id := paste0("CL", sprintf("%06d", n_clusters_dbscan + seq_len(.N)))
  ]

  posiciones[, tipo_punto := data.table::fifelse(cluster_dbscan == 0, "ruido_dbscan", "dbscan")]
  posiciones[, `:=`(
    version_cluster = version_cluster,
    eps_m = eps_m,
    min_pts = min_pts,
    crs = crs,
    redondeo_m = redondeo_m
  )]

  cluster_members_ref <- posiciones[
    ,
    .(
      version_cluster,
      cluster_id,
      punto_ref_id,
      x,
      y,
      cluster_dbscan,
      tipo_punto,
      fecha_min_observada,
      fecha_max_observada,
      n_observaciones,
      n_contenedores,
      eps_m,
      min_pts,
      crs,
      redondeo_m
    )
  ]

  cluster_summary_ref <- cluster_members_ref[
    ,
    {
      x_centroide <- mean(x)
      y_centroide <- mean(y)
      radio <- sqrt((x - x_centroide)^2 + (y - y_centroide)^2)
      .(
        n_puntos = .N,
        n_observaciones = sum(n_observaciones),
        x_centroide = x_centroide,
        y_centroide = y_centroide,
        x_min = min(x),
        x_max = max(x),
        y_min = min(y),
        y_max = max(y),
        radio_max_m = max(radio),
        fecha_min_observada = min(fecha_min_observada),
        fecha_max_observada = max(fecha_max_observada),
        tipo_cluster = if (all(tipo_punto == "ruido_dbscan")) "ruido_unitario" else "dbscan"
      )
    },
    by = .(version_cluster, cluster_id)
  ]

  cluster_metadata <- data.table::data.table(
    version_cluster = version_cluster,
    fecha_entrenamiento = as.Date(Sys.Date()),
    eps_m = eps_m,
    min_pts = min_pts,
    crs = crs,
    redondeo_m = redondeo_m,
    n_puntos_entrenamiento = nrow(cluster_members_ref),
    n_clusters = data.table::uniqueN(cluster_members_ref$cluster_id),
    n_clusters_dbscan = n_clusters_dbscan,
    n_ruido = nrow(cluster_members_ref[tipo_punto == "ruido_dbscan"]),
    pct_ruido = mean(cluster_members_ref$tipo_punto == "ruido_dbscan")
  )

  contenedor_posicion_cluster <- unique(datos_levante[
    ,
    .(
      levante_contenedor_id,
      x = round(as.numeric(x) / redondeo_m) * redondeo_m,
      y = round(as.numeric(y) / redondeo_m) * redondeo_m,
      levante_circuito = if ("levante_circuito" %in% names(datos_levante)) levante_circuito else NA_character_,
      levante_posicion_en_circuito = if ("levante_posicion_en_circuito" %in% names(datos_levante)) levante_posicion_en_circuito else NA_real_
    )
  ])

  contenedor_posicion_cluster <- cluster_members_ref[
    contenedor_posicion_cluster,
    on = .(x, y)
  ][
    ,
    .(
      version_cluster,
      levante_contenedor_id,
      x,
      y,
      cluster_id,
      punto_ref_id,
      levante_circuito,
      levante_posicion_en_circuito
    )
  ]

  n_contenedores_cluster <- contenedor_posicion_cluster[
    ,
    .(n_contenedores = data.table::uniqueN(levante_contenedor_id)),
    by = .(version_cluster, cluster_id)
  ]

  cluster_summary_ref <- n_contenedores_cluster[
    cluster_summary_ref,
    on = .(version_cluster, cluster_id)
  ]

  list(
    cluster_members_ref = cluster_members_ref,
    cluster_summary_ref = cluster_summary_ref,
    cluster_metadata = cluster_metadata,
    contenedor_posicion_cluster = contenedor_posicion_cluster
  )
}
