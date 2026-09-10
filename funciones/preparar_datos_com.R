preparar_datos_com <- function(datos,
                               incidentes_keep = c(
                                 "Contenedor desbordado",
                                 "Basura fuera del contenedor",
                                 "Residuos esparcidos"
                               ),
                               excluir_repetidos = TRUE,
                               crs_origen = 4326,
                               crs_destino = 32721) {
  data.table::setDT(datos)

  datos[, `:=`(
    fecha_de_reclamo = as.POSIXct(fecha_de_reclamo, format = "%Y-%m-%d %H:%M:%OS"),
    fecha_resuelto = as.POSIXct(fecha_resuelto, format = "%Y-%m-%d %H:%M:%OS")
  )]

  datos[, dia := as.IDate(fecha_de_reclamo)]

  datos <- datos[incidente %in% incidentes_keep]

  if (excluir_repetidos && "repetido" %in% names(datos)) {
    datos <- datos[is.na(repetido) | tolower(as.character(repetido)) != "true"]
  }

  if (!requireNamespace("sf", quietly = TRUE)) {
    stop("El paquete sf es necesario para transformar coordenadas COM a CRS ", crs_destino)
  }

  datos[, `:=`(
    longitud = as.numeric(longitud),
    latitud = as.numeric(latitud)
  )]

  datos[, `:=`(
    x = NA_real_,
    y = NA_real_
  )]

  idx_coord <- which(!is.na(datos$longitud) & !is.na(datos$latitud))

  if (length(idx_coord) > 0) {
    pts <- sf::st_as_sf(
      datos[idx_coord],
      coords = c("longitud", "latitud"),
      crs = crs_origen,
      remove = FALSE
    )

    pts <- sf::st_transform(pts, crs_destino)
    coords <- sf::st_coordinates(pts)

    datos[idx_coord, `:=`(
      x = coords[, 1],
      y = coords[, 2]
    )]
  }

  datos[, anio := as.integer(format(dia, "%Y"))]
  datos[, anio_mes := as.integer(format(dia, "%Y%m"))]

  datos[]
}
