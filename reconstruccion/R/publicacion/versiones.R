# Publicacion de productos R08 con versiones inmutables y puntero recuperable.
# Requiere almacen.R. Un unico publicador por prefijo S3; no se simula rename remoto.

# Identificadores portables para versiones, sin directorios ni caracteres especiales.
rf_version_id <- function(id) {
  if (length(id) != 1L || is.na(id) || !grepl("^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$", id)) {
    stop("Identificador de version invalido")
  }
  id
}

# Recolecta fechas cerradas con las mismas reglas COM/ZL que usa la app local.
rf_history_days <- function(source) {
  ds <- arrow::open_dataset(file.path(source, "historico/detalle_cluster_dia"),
    partitioning = arrow::hive_partition(dia_objetivo = arrow::date32(), modelo_id = arrow::utf8()))
  com <- dplyr::collect(dplyr::distinct(dplyr::filter(ds, modelo_id == "com_reclamo",
    estado_observacion == "cerrado", estado_periodo_app == "historico_cerrado"), dia_objetivo))
  zl <- dplyr::collect(dplyr::distinct(dplyr::filter(ds, modelo_id == "zl_problema",
    estado_periodo_app == "historico_cerrado", hay_zl_visita_efectiva == 1L), dia_objetivo))
  list(com_reclamo = sort(as.character(com$dia_objetivo)), zl_problema = sort(as.character(zl$dia_objetivo)))
}

# Crea inventario de integridad; no modifica productos ni promueve modelos.
rf_publication_inventory <- function(source, id) {
  manifest <- readRDS(file.path(source, "publicacion.rds"))
  if (!identical(manifest$status, "ready")) stop("La publicacion de entrada no esta ready")
  for (directory in c("operacional", "historico/detalle_cluster_dia", "historico/serie_historica_com",
      "referencia/maestro_clusters")) {
    if (!dir.exists(file.path(source, directory))) stop("Falta capa: ", directory)
  }
  if (!file.exists(file.path(source, "referencia/barrios_mvd_23_pg.gpkg"))) stop("Falta referencia territorial")
  paths <- list.files(source, recursive = TRUE, full.names = FALSE)
  paths <- paths[!file.info(file.path(source, paths))$isdir]
  if ("inventory.json" %in% paths) stop("La entrada contiene el nombre reservado inventory.json")
  invisible(lapply(paths, rf_object_key))
  files <- data.frame(path = paths, bytes = as.numeric(file.info(file.path(source, paths))$size),
    md5 = unname(tools::md5sum(file.path(source, paths))), stringsAsFactors = FALSE)
  list(contract = "rf_publication_v1", publication_id = rf_version_id(id), status = "ready",
    operational_day = manifest$operational_day, files = files, history_days = rf_history_days(source))
}

# Verifica el contrato de inventario antes de usar sus rutas o estados.
rf_validate_inventory <- function(inventory, id) {
  if (!identical(inventory$contract, "rf_publication_v1") ||
      !identical(inventory$publication_id, rf_version_id(id)) || !identical(inventory$status, "ready") ||
      !is.data.frame(inventory$files) || !all(c("path", "bytes", "md5") %in% names(inventory$files)) ||
      !nrow(inventory$files) || anyDuplicated(inventory$files$path)) stop("Inventario incompatible")
  invisible(lapply(inventory$files$path, rf_object_key))
  if (anyNA(inventory$files) || any(inventory$files$bytes < 0) ||
      any(!grepl("^[0-9a-f]{32}$", inventory$files$md5))) stop("Integridad no declarada")
  invisible(inventory)
}

# Publica una version nueva y verifica cada objeto antes de crear su inventario ready.
# Un fallo deja una version incompleta no activable; reintentar con otro id.
rf_publish_version <- function(source, store, id, fail_after = Inf) {
  id <- rf_version_id(id)
  if (store$backend == "local") {
    source_root <- normalizePath(source, winslash = "/", mustWork = TRUE)
    if (store$root == source_root || startsWith(store$root, paste0(source_root, "/"))) {
      stop("El almacen debe quedar fuera de la publicacion de entrada")
    }
    lock <- file.path(store$root, paste0(".version_", id, ".lock"))
    if (!dir.create(lock, showWarnings = FALSE)) stop("La version tiene otro publicador local")
    on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  }
  prefix <- paste0("versions/", id, "/")
  if (length(rf_store_list(store, prefix))) stop("La version ya existe; elegir otro id")
  inventory <- rf_publication_inventory(source, id)
  scratch <- tempfile("rf_publish_")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  # La identidad de la copia publicada coincide con su directorio/inventario.
  # Se conserva la identidad de origen sin modificar el manifiesto fuente R08.
  manifest <- readRDS(file.path(source, "publicacion.rds"))
  manifest$source_publication_id <- manifest$publication_id
  manifest$publication_id <- id
  published_manifest <- file.path(scratch, "publicacion.rds")
  saveRDS(manifest, published_manifest)
  manifest_row <- match("publicacion.rds", inventory$files$path)
  inventory$files$bytes[manifest_row] <- file.info(published_manifest)$size
  inventory$files$md5[manifest_row] <- unname(tools::md5sum(published_manifest))
  for (i in seq_len(nrow(inventory$files))) {
    item <- inventory$files[i, ]
    key <- paste0(prefix, item$path)
    source_file <- if (item$path == "publicacion.rds") published_manifest else file.path(source, item$path)
    rf_store_put(store, key, source_file)
    check <- rf_store_get(store, key, file.path(scratch, "verify"))
    if (unname(tools::md5sum(check)) != item$md5) stop("Integridad remota incorrecta: ", key)
    if (i >= fail_after) stop("Fallo de publicacion inyectado")
  }
  metadata <- rf_write_json(inventory, file.path(scratch, "inventory.json"))
  rf_store_put(store, paste0(prefix, "inventory.json"), metadata)
  invisible(inventory)
}

# Descarga/verifica objetos en una cache exclusiva de la sesion lectora.
rf_fetch_files <- function(view, paths) {
  files <- view$inventory$files
  if (length(setdiff(paths, files$path))) stop("Objeto no declarado en inventario")
  for (path in paths) {
    item <- files[match(path, files$path), ]
    destination <- file.path(view$root, path)
    valid <- file.exists(destination) && file.info(destination)$size == item$bytes &&
      unname(tools::md5sum(destination)) == item$md5
    if (!valid) {
      rf_store_get(view$store, paste0("versions/", view$id, "/", path), destination)
      if (file.info(destination)$size != item$bytes || unname(tools::md5sum(destination)) != item$md5) {
        stop("Checksum incorrecto: ", path)
      }
    }
  }
  invisible(view$root)
}

# Fija una version una sola vez; una activacion posterior no cambia este lector.
rf_open_publication <- function(store, cache, id = NULL) {
  if (is.null(id)) id <- rf_store_json(store, "current.json")$publication_id
  id <- rf_version_id(id)
  inventory <- rf_store_json(store, paste0("versions/", id, "/inventory.json"))
  rf_validate_inventory(inventory, id)
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  root <- tempfile(paste0(id, "_"), tmpdir = cache)
  dir.create(root)
  view <- list(id = id, inventory = inventory, root = root, store = store)
  rf_fetch_files(view, "publicacion.rds")
  manifest <- readRDS(file.path(root, "publicacion.rds"))
  if (!identical(manifest$status, "ready") || !identical(manifest$publication_id, id)) stop("Manifiesto no ready o version inconsistente")
  view
}

# Activa o revierte a una version ya publicada. Guarda el puntero previo antes del cambio.
# Local usa rename con respaldo y lock; S3 escribe un objeto completo, con publicador unico.
rf_activate_version <- function(store, id, cache, fail_before_pointer = FALSE, fail_after_remove = FALSE) {
  id <- rf_version_id(id)
  if (store$backend == "local") {
    lock <- file.path(store$root, ".publication_lock")
    if (!dir.create(lock, showWarnings = FALSE)) stop("Publicacion local bloqueada")
    on.exit(unlink(lock, recursive = TRUE), add = TRUE)
  }
  view <- rf_open_publication(store, cache, id)
  rf_fetch_files(view, view$inventory$files$path)
  has_current <- "current.json" %in% rf_store_list(store, "current.json")
  scratch <- tempfile("rf_pointer_")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  if (has_current) {
    old <- rf_store_get(store, "current.json", file.path(scratch, "previous.json"))
    rf_store_put(store, "previous.json", old)
  }
  if (fail_before_pointer) stop("Fallo de activacion inyectado; puntero previo preservado")
  pointer <- rf_write_json(list(publication_id = id), file.path(scratch, "current.json"))
  if (store$backend == "local") {
    target <- file.path(store$root, "current.json")
    stage <- file.path(store$root, "current.next.json")
    file.copy(pointer, stage, overwrite = TRUE)
    if (file.exists(target) && !file.remove(target)) stop("No se pudo retirar el puntero previo")
    if (fail_after_remove) stop("Interrupcion local inyectada; restaurar previous.json")
    if (!file.rename(stage, target)) stop("Fallo al activar; recuperar previous.json explicitamente")
  } else {
    rf_store_put(store, "current.json", pointer)
  }
  invisible(id)
}

# Recuperacion explicita: valida la version del respaldo antes de reactivarla.
rf_restore_publication <- function(store, cache) {
  id <- rf_store_json(store, "previous.json")$publication_id
  rf_activate_version(store, id, cache)
}
