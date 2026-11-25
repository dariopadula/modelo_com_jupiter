# Transporte de objetos local/S3. No instala dependencias ni conserva credenciales.
# Las operaciones S3 pueden inyectarse en pruebas; el cliente real es administrado por CML.

# Acepta claves relativas sin segmentos ambiguos ni escapes del almacen.
rf_object_key <- function(key) {
  if (!is.character(key) || length(key) != 1L || is.na(key) || !nzchar(key) ||
      grepl("[\\\\:]|^/|/$|//", key) ||
      any(strsplit(key, "/", fixed = TRUE)[[1L]] %in% c(".", ".."))) {
    stop("Clave de objeto insegura")
  }
  key
}

# Crea el cliente CML instalado. No solicita ni descarga paquetes Python.
rf_cml_ops <- function(connection) {
  if (!requireNamespace("reticulate", quietly = TRUE)) stop("Se requiere reticulate instalado")
  if (!reticulate::py_available(initialize = FALSE) &&
      !file.exists(Sys.getenv("RETICULATE_PYTHON", ""))) {
    stop("Definir RETICULATE_PYTHON con el interprete ya instalado en Cloudera")
  }
  if (!reticulate::py_module_available("cml.data_v1")) {
    stop("Se requiere reticulate y cml.data_v1 instalado en Cloudera")
  }
  client <- reticulate::import("cml.data_v1")$get_connection(connection)$get_base_connection()
  list(
    list = function(bucket, prefix) {
      keys <- character()
      token <- NULL
      repeat {
        args <- list(Bucket = bucket, Prefix = prefix)
        if (!is.null(token)) args$ContinuationToken <- token
        result <- do.call(client$list_objects_v2, args)
        keys <- c(keys, vapply(result$Contents, function(x) as.character(x$Key), character(1)))
        if (!isTRUE(result$IsTruncated)) break
        token <- result$NextContinuationToken
      }
      keys
    },
    download = function(bucket, key, destination) {
      client$download_file(Bucket = bucket, Key = key, Filename = destination)
    },
    upload = function(bucket, key, source) {
      client$upload_file(Filename = source, Bucket = bucket, Key = key)
    }
  )
}

# Resuelve un almacen segun su propietario; los tres selectores son independientes.
rf_store <- function(config, role, local_root, ops = NULL) {
  values <- config$values
  selector <- switch(role, input = "INGESTA_INPUT_BACKEND", pipeline = "PIPELINE_STORAGE_BACKEND",
    app = "APP_DATA_SOURCE", stop("Propietario de almacen desconocido"))
  backend <- values[[selector]]
  if (backend == "local") {
    dir.create(local_root, recursive = TRUE, showWarnings = FALSE)
    return(list(backend = backend, root = normalizePath(local_root, winslash = "/", mustWork = TRUE)))
  }
  connection <- values[[if (role == "app") "APP_S3_CONNECTION" else "PIPELINE_S3_CONNECTION"]]
  bucket <- values[[if (role == "app") "APP_S3_BUCKET" else "PIPELINE_S3_BUCKET"]]
  prefix <- values[[switch(role, input = "INGESTA_S3_PREFIX", pipeline = "PIPELINE_S3_PREFIX",
    app = "APP_S3_PREFIX")]]
  rf_object_key(prefix)
  if (is.null(ops)) ops <- rf_cml_ops(connection)
  list(backend = backend, bucket = bucket, prefix = prefix, ops = ops)
}

# Lista solo un prefijo del almacen; devuelve claves relativas al propietario.
rf_store_list <- function(store, prefix) {
  rf_object_key(sub("/$", "", prefix))
  if (store$backend == "local") {
    files <- list.files(store$root, recursive = TRUE, full.names = FALSE, all.files = TRUE)
    return(files[startsWith(files, prefix)])
  }
  keys <- store$ops$list(store$bucket, paste0(store$prefix, "/", prefix))
  substring(keys[startsWith(keys, paste0(store$prefix, "/", prefix))], nchar(store$prefix) + 2L)
}

# Descarga una clave exacta. La cache es un destino aislado, nunca persistencia canonica.
rf_store_get <- function(store, key, destination) {
  rf_object_key(key)
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  if (store$backend == "local") {
    if (!file.copy(file.path(store$root, key), destination, overwrite = TRUE)) stop("Objeto local ausente: ", key)
  } else {
    store$ops$download(store$bucket, paste0(store$prefix, "/", key), destination)
  }
  if (!file.exists(destination)) stop("Descarga incompleta: ", key)
  destination
}

# Escribe un objeto; para versiones, el propietario exige claves nuevas.
rf_store_put <- function(store, key, source) {
  rf_object_key(key)
  if (!file.exists(source) || dir.exists(source)) stop("Falta archivo a persistir")
  if (store$backend == "local") {
    destination <- file.path(store$root, key)
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(source, destination, overwrite = TRUE)) stop("Fallo de persistencia: ", key)
  } else {
    store$ops$upload(store$bucket, paste0(store$prefix, "/", key), source)
  }
  invisible(key)
}

# Serializacion JSON propia para metadatos sin secretos.
rf_write_json <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(value, path, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
  path
}

# Lee JSON por clave exacta, liberando solamente el archivo temporal creado aqui.
rf_store_json <- function(store, key) {
  path <- tempfile("rf_metadata_")
  on.exit(unlink(path), add = TRUE)
  rf_store_get(store, key, path)
  jsonlite::read_json(path, simplifyVector = TRUE)
}
