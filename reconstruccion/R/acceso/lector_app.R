# Fija la publicacion por carga. La cache y sus objetos pertenecen a una sola version.
# Una publicacion directa R08 sigue siendo valida para compatibilidad local.
rf_app_context <- function(config, publication = "", store_root = "", ops = NULL) {
  backend <- config$values[["APP_DATA_SOURCE"]]
  if (backend == "local" && !nzchar(store_root)) {
    if (!nzchar(publication)) publication <- file.path(config$root, "runtime/r08_app/publicacion_piloto")
    root <- normalizePath(publication, winslash = "/", mustWork = TRUE)
    manifest <- readRDS(file.path(root, "publicacion.rds"))
    if (!identical(manifest$status, "ready")) stop("Publicacion directa no ready")
    return(list(root = root, manifest = manifest, backend = backend, view = NULL))
  }
  store <- rf_store(config, "app", store_root, ops)
  cache <- file.path(config$values[["RF_RUNTIME_PATH"]], "cache_app")
  view <- rf_open_publication(store, cache)
  paths <- view$inventory$files$path
  # El detalle historico se materializa despues, solo por fecha y familia elegidas.
  rf_fetch_files(view, paths[!startsWith(paths, "historico/detalle_cluster_dia/")])
  list(root = view$root, manifest = readRDS(file.path(view$root, "publicacion.rds")),
    backend = backend, view = view)
}

# Descarga solo las particiones exactas declaradas en el inventario de la version fija.
rf_app_fetch_day <- function(context, day, family) {
  if (is.na(as.Date(day)) || !family %in% c("com_reclamo", "zl_problema")) stop("Fecha/modelo invalidos")
  view <- context$view
  if (is.null(view)) return(invisible(context$root))
  prefix <- paste0("historico/detalle_cluster_dia/dia_objetivo=", as.Date(day), "/modelo_id=", family, "/")
  paths <- view$inventory$files$path
  paths <- paths[startsWith(paths, prefix)]
  if (!length(paths)) stop("No existe detalle para la fecha/modelo seleccionados")
  rf_fetch_files(view, paths)
}
