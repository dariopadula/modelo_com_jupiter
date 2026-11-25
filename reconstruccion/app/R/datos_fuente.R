# Fija el puntero local/S3 una sola vez; conserva publicacion directa R08.
.rf_app_context <- rf_app_context(rf_config(root),
  publication = Sys.getenv("RF_APP_PUBLICATION", ""), store_root = Sys.getenv("RF_APP_STORE", ""))
.rf_publication_root <- .rf_app_context$root
.rf_publication <- .rf_app_context$manifest
if (!identical(.rf_publication$status, "ready")) {
  stop("La publicacion seleccionada no esta validada")
}

fuente_datos_app <- function() .rf_app_context$backend
usar_s3_app <- function() identical(.rf_app_context$backend, "cloudera_s3")
usar_detalle_por_particion_app <- function() !is.null(.rf_app_context$view)
# Las fechas del inventario ya aplican los criterios de cierre COM/ZL originales.
listar_dias_detalle_s3_app <- function(modelo) {
  as.character(unlist(.rf_app_context$view$inventory$history_days[[modelo]]))
}
dias_validacion_app <- function() .rf_publication$days_validation
resolver_path_datos_app <- function() file.path(.rf_publication_root, "operacional")
resolver_path_serie_app <- function() file.path(.rf_publication_root, "historico", "serie_historica_com")
resolver_path_maestro_app <- function() file.path(.rf_publication_root, "referencia", "maestro_clusters")
resolver_path_barrios_app <- function() file.path(.rf_publication_root, "referencia", "barrios_mvd_23_pg.gpkg")

# Declara el tipo de las particiones y filtra fecha/modelo antes de collect.
abrir_detalle_local_app <- function() {
  arrow::open_dataset(file.path(.rf_publication_root, "historico", "detalle_cluster_dia"),
    partitioning = arrow::hive_partition(dia_objetivo = arrow::date32(), modelo_id = arrow::utf8()))
}

cargar_detalle_dia_app <- function(fecha, modelo, ds_local = NULL) {
  rf_app_fetch_day(.rf_app_context, fecha, modelo)
  ds <- if (is.null(ds_local)) abrir_detalle_local_app() else ds_local
  day <- as.Date(fecha)
  data.table::as.data.table(as.data.frame(
    dplyr::collect(dplyr::filter(ds, dia_objetivo == !!day, modelo_id == !!modelo))
  ))
}

# El dia operativo es el registrado al construir la publicacion.
cargar_predicciones_operacion_app <- function() {
  day <- as.Date(.rf_publication$operational_day)
  ds <- arrow::open_dataset(file.path(resolver_path_datos_app(), "predicciones_operativas_cluster_dia"))
  predictions <- data.table::as.data.table(as.data.frame(dplyr::collect(dplyr::filter(ds, dia_objetivo == !!day))))
  if (!nrow(predictions) || !setequal(unique(predictions$modelo_id), c("com_reclamo", "zl_problema"))) {
    stop("La publicacion no contiene ambas familias para el dia operativo")
  }
  predictions[, dia_objetivo := data.table::as.IDate(dia_objetivo)]
  list(predicciones = predictions, dia_operativo = data.table::as.IDate(day))
}
