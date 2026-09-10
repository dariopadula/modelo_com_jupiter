cargar_datos_operacion <- function() {
  path_base <- resolver_path_datos_app()
  path_pred <- file.path(path_base, "predicciones_operativas_cluster_dia")
  ds_pred <- arrow::open_dataset(path_pred, format = "parquet")

  resumen_fecha <- ds_pred |>
    dplyr::summarise(dia_operativo = max(dia_objetivo, na.rm = TRUE)) |>
    dplyr::collect() |>
    data.table::as.data.table()
  dia_operativo <- data.table::as.IDate(resumen_fecha$dia_operativo[[1]])

  pred <- ds_pred |>
    dplyr::filter(dia_objetivo == !!as.Date(dia_operativo)) |>
    dplyr::collect() |>
    data.table::as.data.table()
  pred[, dia_objetivo := data.table::as.IDate(dia_objetivo)]

  path_maestro <- Sys.getenv(
    "APP_CLUSTER_PATH",
    unset = "data/referencia/maestro_clusters"
  )
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

  path_barrios <- Sys.getenv(
    "APP_BARRIOS_PATH",
    unset = "data/referencia/barrios_mvd_23_pg.gpkg"
  )
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

  path_historico <- Sys.getenv(
    "APP_HISTORICO_PATH",
    unset = "data/historico"
  )
  path_serie <- file.path(path_historico, "serie_historica_com")
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
    path_base = path_base,
    predicciones = pred,
    centroides = centroides,
    barrios = barrios,
    agregado_dia = agregado_dia,
    agregado_barrio = agregado_barrio,
    version_cluster = version_objetivo,
    dia_operativo = dia_operativo
  )
}

