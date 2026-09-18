cargar_datos_operacion <- function() {
  operacion <- cargar_predicciones_operacion_app()
  pred <- operacion$predicciones
  dia_operativo <- operacion$dia_operativo

  path_maestro <- resolver_path_maestro_app()
  centroides <- leer_dataset_app(path_maestro)

  version_objetivo <- sort(unique(pred$version_cluster))
  version_objetivo <- version_objetivo[length(version_objetivo)]
  centroides <- centroides[
    version_cluster == version_objetivo & !is.na(cluster_id)
  ]
  if (!nrow(centroides)) {
    stop("El maestro territorial no contiene la version ", version_objetivo)
  }

  centroides_sf <- sf::st_as_sf(
    centroides,
    coords = c("x", "y"),
    crs = 32721,
    remove = FALSE
  ) |>
    sf::st_transform(4326)
  coords <- sf::st_coordinates(centroides_sf)
  centroides[, `:=`(lng = coords[, 1], lat = coords[, 2])]

  path_barrios <- resolver_path_barrios_app()
  barrios <- if (file.exists(path_barrios)) {
    barrios_raw <- sf::st_read(path_barrios, quiet = TRUE)
    barrios_raw <- barrios_raw[
      !is.na(barrios_raw$NOMBARRIOINE) &
        barrios_raw$NOMBARRIOINE != "N/A" &
        !is.na(barrios_raw$CODBARRIOINE),
    ]
    barrios_raw$cod_barrio_ine <- as.character(barrios_raw$CODBARRIOINE)
    barrios_raw[, c("NOMBARRIOINE", "cod_barrio_ine")]
  } else {
    sf::st_sf()
  }

  path_serie <- resolver_path_serie_app()
  ds_serie <- arrow::open_dataset(path_serie, format = "parquet")
  serie_dia <- ds_serie |>
    dplyr::filter(
      escenario == "P3_compacto",
      dia_objetivo == !!as.Date(dia_operativo)
    ) |>
    dplyr::collect() |>
    data.table::as.data.table()

  agregado_dia <- serie_dia[nivel_territorial == "montevideo", .(
    dia_objetivo = data.table::as.IDate(dia_objetivo),
    predicho = as.numeric(clusters_estimados),
    observado = as.integer(clusters_observados),
    escenario,
    split_modelo
  )]
  agregado_barrio <- serie_dia[nivel_territorial == "barrio", .(
    dia_objetivo = data.table::as.IDate(dia_objetivo),
    barrio = territorio_nombre,
    predicho = as.numeric(clusters_estimados),
    observado = as.integer(clusters_observados),
    n_clusters = as.integer(clusters_evaluados),
    escenario,
    split_modelo
  )]

  codigos_barrio <- unique(centroides[
    !is.na(barrio) & !is.na(cod_barrio_ine),
    .(barrio, cod_barrio_ine = as.character(cod_barrio_ine))
  ])
  if (nrow(agregado_barrio)) {
    agregado_barrio <- codigos_barrio[agregado_barrio, on = "barrio"]
  }

  pred <- centroides[pred, on = "cluster_id"]
  pred <- pred[!is.na(lng) & !is.na(lat)]
  data.table::setorder(pred, modelo_id, ranking_dia)

  list(
    fuente = fuente_datos_app(),
    predicciones = pred,
    centroides = centroides,
    barrios = barrios,
    agregado_dia = agregado_dia,
    agregado_barrio = agregado_barrio,
    version_cluster = version_objetivo,
    dia_operativo = dia_operativo
  )
}
