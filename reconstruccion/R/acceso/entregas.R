# Entregas fuentes_v2: seleccion acotada de objetos y marcas declaradas por el productor.
# El cierre nunca se infiere del ultimo evento ni de la fecha de descarga.

# Lee timestamps completos, preservando hora y offset en vez de aceptar solo la fecha.
rf_delivery_time <- function(value) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?$", value)) {
    stop("Timestamp contractual invalido")
  }
  value <- sub("T", " ", value, fixed = TRUE)
  value <- sub("Z$", "+0000", value)
  value <- sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", value)
  format <- if (grepl("[+-][0-9]{4}$", value)) "%Y-%m-%d %H:%M:%OS%z" else "%Y-%m-%d %H:%M:%OS"
  result <- as.POSIXct(strptime(value, format, tz = "America/Montevideo"))
  if (is.na(result)) stop("Timestamp contractual invalido")
  result
}

# Esquema crudo minimo migrado de ii_required_columns, sin filtros de negocio.
rf_raw_columns <- function(family) {
  switch(family,
    com = c("id", "municipio", "circuito", "fecha_de_reclamo", "estado", "repetido",
      "fecha_resuelto", "incidente", "latitud", "longitud", "tipo_de_reclamo", "anio", "anio_mes"),
    levante = c("levante_contenedor_id", "levante_fecha_levante", "levante_circuito",
      "levante_posicion_en_circuito", "levante_activo", "levante_motivo_no_levante_id",
      "levante_motivo_no_levante_descripcion", "levante_fact", "levante_porcentaje_llenado",
      "levante_periodo", "levante_longitud", "levante_latitud", "anio", "anio_mes"),
    stop("Fuente desconocida"))
}

# Valida particiones mensuales antes de incorporarlas a consultas o rutas.
rf_months <- function(months) {
  months <- as.character(unlist(months))
  if (!length(months) || anyNA(months) || any(!grepl("^[0-9]{6}$", months)) ||
      any(is.na(as.Date(paste0(months, "01"), "%Y%m%d")))) stop("Particiones mensuales invalidas")
  sort(unique(months))
}

# Meses completos necesarios para el contexto de levantes.
rf_context_months <- function(months, context_days = 90L) {
  months <- rf_months(months)
  if (length(context_days) != 1L || is.na(context_days) || context_days < 0) stop("Contexto invalido")
  start <- as.Date(paste0(min(months), "01"), "%Y%m%d") - context_days
  finish <- as.Date(paste0(max(months), "01"), "%Y%m%d")
  format(seq(as.Date(format(start, "%Y-%m-01")), finish, by = "month"), "%Y%m")
}

# Normaliza objects de JSON sin depender de la simplificacion de listas de jsonlite.
rf_delivery_objects <- function(source) {
  objects <- source$objects
  if (is.data.frame(objects)) objects <- lapply(seq_len(nrow(objects)), function(i) as.list(objects[i, ]))
  if (!is.list(objects) || !length(objects)) stop("Entrega sin objetos declarados")
  for (object in objects) {
    rf_object_key(object$key)
    rf_months(object$partitions)
    if (length(object$row_count) != 1L || is.na(object$row_count) || object$row_count < 0) {
      stop("Conteo de objeto invalido")
    }
  }
  if (anyDuplicated(vapply(objects, function(x) x$key, character(1)))) stop("Objetos duplicados")
  objects
}

# Verifica entrega y cierres antes de consultar/descargar datos crudos.
# require_closed=FALSE sirve solo para inspeccion, no habilita operacion diaria.
rf_validate_delivery <- function(manifest, context_days = 90L, require_closed = TRUE) {
  if (!identical(manifest$contract_version, "fuentes_v2") ||
      !manifest$status %in% c("lista", "validada") ||
      !identical(manifest$timezone, "America/Montevideo") ||
      is.null(manifest$schema_version)) stop("Contrato de entrega invalido")
  rf_delivery_time(manifest$extract_timestamp)
  rf_version_id(manifest$delivery_id)
  for (family in c("com", "levante")) {
    item <- manifest[[family]]
    required <- c("complete_through", "available_through_timestamp", "min_event_timestamp",
      "max_event_timestamp", "partitions_replaced", "row_count_by_partition", "replacement_scope_by_partition", "objects")
    if (!all(required %in% names(item))) stop("Faltan campos de entrega en ", family)
    months <- rf_months(item$partitions_replaced)
    if (!setequal(names(item$row_count_by_partition), months) ||
        !setequal(names(item$replacement_scope_by_partition), months) ||
        any(unlist(item$replacement_scope_by_partition) != "complete") ||
        anyNA(unlist(item$row_count_by_partition)) || any(unlist(item$row_count_by_partition) < 0)) {
      stop("Particion parcial o conteos incompatibles: ", family)
    }
    closed <- item$complete_through
    available <- item$available_through_timestamp
    if (require_closed && (is.null(closed) || !length(closed) || is.na(as.Date(closed)))) {
      stop("Cierre desconocido: ", family)
    }
    available_time <- rf_delivery_time(available)
    if (!is.null(closed) && as.Date(closed) > as.Date(available_time, tz = "America/Montevideo")) stop("Cierre posterior a disponibilidad")
    objects <- rf_delivery_objects(item)
    covered <- unique(unlist(lapply(objects, function(x) as.character(unlist(x$partitions)))))
    needed <- if (family == "levante") rf_context_months(months, context_days) else months
    if (length(setdiff(needed, covered))) stop("Faltan particiones o contexto: ", family)
    if (family == "levante" && context_days > 0L) {
      start <- as.Date(paste0(min(months), "01"), "%Y%m%d") - context_days
      first_event <- as.Date(substr(item$min_event_timestamp, 1L, 10L))
      if (length(first_event) != 1L || is.na(first_event) || first_event > start) {
        stop("La cobertura de levantes no acredita el contexto requerido")
      }
    }
  }
  invisible(manifest)
}

# Materializa solo los objetos declarados que cubren particiones objetivo/contexto.
# Devuelve rutas propias, cierres separados y procedencia; no calcula features.
rf_materialize_delivery <- function(store, manifest_key, cache, context_days = 90L) {
  manifest <- rf_store_json(store, manifest_key)
  rf_validate_delivery(manifest, context_days)
  dir.create(cache, recursive = TRUE, showWarnings = FALSE)
  destination <- tempfile(paste0(manifest$delivery_id, "_"), tmpdir = cache)
  dir.create(destination)
  paths <- list()
  for (family in c("com", "levante")) {
    item <- manifest[[family]]
    months <- rf_months(item$partitions_replaced)
    needed <- if (family == "levante") rf_context_months(months, context_days) else months
    objects <- rf_delivery_objects(item)
    objects <- Filter(function(x) any(as.character(unlist(x$partitions)) %in% needed), objects)
    paths[[family]] <- file.path(destination, family)
    for (object in objects) {
      target <- file.path(paths[[family]], object$key)
      rf_store_get(store, object$key, target)
      if (!is.null(object$md5) && unname(tools::md5sum(target)) != object$md5) stop("Checksum crudo incorrecto")
      object_dataset <- arrow::open_dataset(target, partitioning = NULL)
      if (length(setdiff(rf_raw_columns(family), names(object_dataset)))) stop("Esquema crudo incompleto: ", family)
      data <- dplyr::collect(dplyr::count(object_dataset, anio_mes))
      if (sum(data$n) != object$row_count || anyNA(data$anio_mes) ||
          any(!as.character(data$anio_mes) %in% as.character(unlist(object$partitions)))) {
        stop("Objeto incompatible con su declaracion: ", object$key)
      }
    }
    # Conteos por particion objetivo, incluidos meses declarados con cero eventos.
    ds <- arrow::open_dataset(paths[[family]], partitioning = NULL)
    counts <- dplyr::collect(dplyr::count(ds, anio_mes))
    actual <- stats::setNames(counts$n, as.character(counts$anio_mes))
    for (month in months) {
      count <- if (month %in% names(actual)) actual[[month]] else 0
      if (count != item$row_count_by_partition[[month]]) stop("Conteo de particion incorrecto: ", family, "/", month)
    }
  }
  list(delivery_id = manifest$delivery_id, raw_com_path = paths$com, raw_levante_path = paths$levante,
    com_complete_through = as.Date(manifest$com$complete_through),
    levante_complete_through = as.Date(manifest$levante$complete_through),
    levante_available_through_timestamp = rf_delivery_time(manifest$levante$available_through_timestamp), manifest = manifest)
}

# Publica una entrega nueva con manifiesto al final. No sobrescribe objetos existentes.
# El productor debe usar un prefijo aislado por entrega, tambien en S3.
rf_publish_delivery <- function(source, store, manifest_key, cache) {
  rf_object_key(manifest_key)
  local <- list(backend = "local", root = normalizePath(source, winslash = "/", mustWork = TRUE))
  # Verifica esquema, contexto y conteos antes de transferir un solo objeto.
  delivery <- rf_materialize_delivery(local, "manifest.json", cache)
  manifest <- delivery$manifest
  objects <- unlist(lapply(c("com", "levante"), function(family) {
    vapply(rf_delivery_objects(manifest[[family]]), function(x) x$key, character(1))
  }), use.names = FALSE)
  for (key in c(objects, manifest_key)) {
    if (key %in% rf_store_list(store, key)) stop("El objeto de entrega ya existe: ", key)
  }
  scratch <- tempfile("rf_delivery_verify_", tmpdir = cache)
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  for (key in objects) {
    original <- file.path(source, key)
    rf_store_put(store, key, original)
    downloaded <- rf_store_get(store, key, file.path(scratch, "verify"))
    if (unname(tools::md5sum(original)) != unname(tools::md5sum(downloaded))) stop("Fallo de integridad de entrega")
  }
  rf_store_put(store, manifest_key, file.path(source, "manifest.json"))
  invisible(manifest$delivery_id)
}
