chequear_espacial_com_levante <- function(datos_com,
                                          datos_levante,
                                          sample_n = 5000,
                                          seed = 123,
                                          crs = 32721) {
  if (!requireNamespace("FNN", quietly = TRUE)) {
    stop("El paquete FNN es necesario para calcular vecinos mas cercanos")
  }

  data.table::setDT(datos_com)
  data.table::setDT(datos_levante)

  cols_com <- c("x", "y")
  cols_levante <- c("x", "y")

  if (!all(cols_com %in% names(datos_com))) {
    stop("datos_com debe tener columnas x e y en CRS ", crs)
  }

  if (!all(cols_levante %in% names(datos_levante))) {
    if (all(c("levante_longitud", "levante_latitud") %in% names(datos_levante))) {
      datos_levante[, `:=`(
        x = as.numeric(levante_longitud),
        y = as.numeric(levante_latitud)
      )]
    } else {
      stop("datos_levante debe tener columnas x/y o levante_longitud/levante_latitud")
    }
  }

  com_xy <- datos_com[
    !is.na(x) & !is.na(y),
    .(x = as.numeric(x), y = as.numeric(y))
  ]

  levante_xy <- unique(datos_levante[
    !is.na(x) & !is.na(y),
    .(x = as.numeric(x), y = as.numeric(y))
  ])

  if (nrow(com_xy) == 0) stop("No hay coordenadas validas en COM")
  if (nrow(levante_xy) == 0) stop("No hay coordenadas validas en levantes")

  bbox <- data.table::rbindlist(list(
    com = com_xy[, .(
      tabla = "com",
      n = .N,
      min_x = min(x),
      max_x = max(x),
      min_y = min(y),
      max_y = max(y)
    )],
    levante = levante_xy[, .(
      tabla = "levante",
      n = .N,
      min_x = min(x),
      max_x = max(x),
      min_y = min(y),
      max_y = max(y)
    )]
  ))

  set.seed(seed)
  if (nrow(com_xy) > sample_n) {
    com_sample <- com_xy[sample.int(.N, sample_n)]
  } else {
    com_sample <- com_xy
  }

  nn <- FNN::get.knnx(
    data = as.matrix(levante_xy[, .(x, y)]),
    query = as.matrix(com_sample[, .(x, y)]),
    k = 1
  )

  dist <- nn$nn.dist[, 1]

  resumen_distancias <- data.table::data.table(
    crs = crs,
    n_com = nrow(com_xy),
    n_levante_posiciones = nrow(levante_xy),
    n_com_muestra = nrow(com_sample),
    dist_min = min(dist),
    dist_p25 = as.numeric(stats::quantile(dist, 0.25, names = FALSE)),
    dist_mediana = stats::median(dist),
    dist_media = mean(dist),
    dist_p75 = as.numeric(stats::quantile(dist, 0.75, names = FALSE)),
    dist_p90 = as.numeric(stats::quantile(dist, 0.90, names = FALSE)),
    dist_p95 = as.numeric(stats::quantile(dist, 0.95, names = FALSE)),
    dist_max = max(dist),
    pct_menor_50m = mean(dist <= 50),
    pct_menor_100m = mean(dist <= 100),
    pct_menor_200m = mean(dist <= 200)
  )

  list(
    crs = crs,
    bbox = bbox,
    resumen_distancias = resumen_distancias
  )
}
