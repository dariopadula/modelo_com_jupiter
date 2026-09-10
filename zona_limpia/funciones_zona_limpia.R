incidentes_modelo_com <- function() {
  c(
    "Contenedor desbordado",
    "Basura fuera del contenedor",
    "Residuos esparcidos"
  )
}

meses_excluidos_analisis_zona_limpia <- function() {
  c(202508L, 202509L, 202601L, 202602L)
}

filtrar_periodo_analisis_zona_limpia <- function(datos,
                                                  meses_excluidos = meses_excluidos_analisis_zona_limpia()) {
  data.table::setDT(datos)

  if (!"anio_mes" %in% names(datos)) {
    if (!"dia" %in% names(datos)) {
      stop("Para filtrar periodo Zona Limpia se necesita columna anio_mes o dia.")
    }
    datos[, anio_mes := as.integer(format(dia, "%Y%m"))]
  }

  datos[!anio_mes %in% meses_excluidos]
}

normalizar_incidente_zona_limpia <- function(x) {
  x <- as.character(x)
  x <- gsub("[\u2010\u2011\u2012\u2013\u2014\u2212]", "-", x, perl = TRUE)
  x <- gsub("[[:space:]]+", " ", x)
  x <- gsub("[[:space:]]*-[[:space:]]*", " - ", x)
  trimws(x)
}

clasificar_tipo_zona_limpia <- function(incidente_zona_limpia_normalizado) {
  x <- tolower(as.character(incidente_zona_limpia_normalizado))
  tipo <- rep(NA_character_, length(x))

  tipo[!is.na(x) & grepl("no visitado", x, fixed = TRUE)] <- "no_visitado"
  tipo[!is.na(x) & grepl("no se encuentra", x, fixed = TRUE)] <- "no_se_encuentra"
  tipo[!is.na(x) & grepl("basura fuera", x, fixed = TRUE) & is.na(tipo)] <- "basura_fuera"
  tipo[!is.na(x) & grepl("contenedor desbordado", x, fixed = TRUE) & is.na(tipo)] <- "contenedor_desbordado"
  tipo[!is.na(x) & grepl("voluminosos", x, fixed = TRUE) & is.na(tipo)] <- "voluminosos"
  tipo[!is.na(x) & grepl("no se pudo realizar", x, fixed = TRUE) & is.na(tipo)] <- "no_se_pudo_realizar"
  tipo[!is.na(x) & grepl("limpio", x, fixed = TRUE) & is.na(tipo)] <- "limpio"
  tipo[!is.na(x) & is.na(tipo)] <- "pendiente_mapeo"

  tipo
}

agregar_indicadores_zona_limpia <- function(zl) {
  data.table::setDT(zl)

  zl[, es_zl_problema_comparable := tipo_zona_limpia %in% c(
    "basura_fuera",
    "contenedor_desbordado"
  )]
  zl[, es_zl_voluminosos := tipo_zona_limpia == "voluminosos"]
  zl[, es_zl_limpio := tipo_zona_limpia == "limpio"]
  zl[, es_zl_no_visitado := tipo_zona_limpia == "no_visitado"]
  zl[, es_zl_no_encontrado := tipo_zona_limpia == "no_se_encuentra"]
  zl[, es_zl_no_realizado := tipo_zona_limpia == "no_se_pudo_realizar"]
  zl[, es_zl_visita_efectiva := es_zl_problema_comparable | es_zl_voluminosos | es_zl_limpio]

  zl[]
}

clasificar_comparacion_com_zona_limpia <- function(hay_com,
                                                   hay_zl_problema_comparable,
                                                   hay_zl_voluminosos,
                                                   hay_zl_limpio,
                                                   hay_zl_visita_efectiva,
                                                   hay_zl_sin_validacion) {
  data.table::fcase(
    hay_com & hay_zl_problema_comparable,
    "ambos_reportan_problema",
    !hay_com & hay_zl_problema_comparable,
    "solo_zona_limpia_problema",
    hay_com & hay_zl_voluminosos & !hay_zl_problema_comparable,
    "com_y_zl_voluminosos",
    !hay_com & hay_zl_voluminosos & !hay_zl_problema_comparable,
    "solo_zona_limpia_voluminosos",
    hay_com & hay_zl_limpio & !hay_zl_problema_comparable,
    "solo_com_zl_limpio",
    !hay_com & hay_zl_limpio & !hay_zl_problema_comparable,
    "ambos_sin_problema_observado",
    hay_com & !hay_zl_visita_efectiva & hay_zl_sin_validacion,
    "com_sin_validacion_zl",
    !hay_com & !hay_zl_visita_efectiva & hay_zl_sin_validacion,
    "zl_sin_visita_efectiva_sin_com",
    hay_com,
    "solo_com_sin_zl",
    default = "sin_com_sin_zl"
  )
}

leer_mapeo_incidentes_zona_limpia <- function(path = "zona_limpia/mapeo_incidentes_zona_limpia.csv") {
  if (!file.exists(path)) {
    stop("No existe el archivo de mapeo Zona Limpia: ", path)
  }

  mapeo <- data.table::fread(path, encoding = "UTF-8")
  cols_req <- c("incidente_zona_limpia_normalizado", "incidente_zona_limpia_mapeado")
  if (!all(cols_req %in% names(mapeo))) {
    stop("El mapeo debe tener columnas: ", paste(cols_req, collapse = ", "))
  }

  mapeo[, incidente_zona_limpia_normalizado := normalizar_incidente_zona_limpia(incidente_zona_limpia_normalizado)]
  mapeo[, incidente_zona_limpia_mapeado := normalizar_incidente_zona_limpia(incidente_zona_limpia_mapeado)]

  duplicados <- mapeo[
    ,
    .(n_mapeados = data.table::uniqueN(incidente_zona_limpia_mapeado)),
    by = incidente_zona_limpia_normalizado
  ][n_mapeados > 1]
  if (nrow(duplicados) > 0L) {
    stop("Hay etiquetas Zona Limpia con mas de un mapeo canonico.")
  }

  unique(mapeo)
}

preparar_datos_com_completo <- function(datos,
                                        incidentes_modelo = incidentes_modelo_com(),
                                        path_mapeo_zona_limpia = "zona_limpia/mapeo_incidentes_zona_limpia.csv",
                                        excluir_repetidos = TRUE,
                                        crs_origen = 4326,
                                        crs_destino = 32721) {
  data.table::setDT(datos)
  mapeo_zona_limpia <- leer_mapeo_incidentes_zona_limpia(path_mapeo_zona_limpia)

  datos[, incidente_original := as.character(incidente)]
  datos[, incidente_zona_limpia_normalizado := normalizar_incidente_zona_limpia(incidente_original)]
  datos[, es_zona_limpia := grepl("^zona limpia", tolower(incidente_zona_limpia_normalizado))]
  datos[, es_incidente_modelo := incidente_original %in% incidentes_modelo]

  datos <- datos[es_incidente_modelo == TRUE | es_zona_limpia == TRUE]

  datos[, incidente_normalizado := data.table::fifelse(
    es_zona_limpia == TRUE,
    incidente_zona_limpia_normalizado,
    incidente_original
  )]
  datos[es_zona_limpia != TRUE, incidente_zona_limpia_normalizado := NA_character_]

  datos <- mapeo_zona_limpia[
    datos,
    on = "incidente_zona_limpia_normalizado"
  ]
  datos[
    es_zona_limpia == TRUE & is.na(incidente_zona_limpia_mapeado),
    incidente_zona_limpia_mapeado := "Zona limpia - Sin mapeo"
  ]
  datos[
    es_zona_limpia != TRUE,
    incidente_zona_limpia_mapeado := NA_character_
  ]
  datos[, zona_limpia_sin_mapeo := es_zona_limpia == TRUE & incidente_zona_limpia_mapeado == "Zona limpia - Sin mapeo"]
  datos[, tipo_zona_limpia := clasificar_tipo_zona_limpia(incidente_zona_limpia_mapeado)]

  datos[, `:=`(
    fecha_de_reclamo = as.POSIXct(fecha_de_reclamo, format = "%Y-%m-%d %H:%M:%OS"),
    fecha_resuelto = as.POSIXct(fecha_resuelto, format = "%Y-%m-%d %H:%M:%OS")
  )]

  datos[, dia := as.IDate(fecha_de_reclamo)]

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
