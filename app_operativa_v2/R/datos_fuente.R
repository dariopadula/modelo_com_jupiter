.app_fuente_cache <- new.env(parent = emptyenv())

fuente_datos_app <- function() {
  fuente <- tolower(trimws(Sys.getenv("APP_DATA_SOURCE", unset = "local")))
  aliases <- c(s3 = "cloudera_s3", cloudera = "cloudera_s3")
  if (fuente %in% names(aliases)) fuente <- aliases[[fuente]]
  if (!fuente %in% c("local", "cloudera_s3")) {
    stop(
      "APP_DATA_SOURCE debe ser 'local' o 'cloudera_s3'; se recibio: ",
      fuente
    )
  }
  fuente
}

usar_s3_app <- function() {
  identical(fuente_datos_app(), "cloudera_s3")
}

dias_validacion_app <- function() {
  valor <- suppressWarnings(as.integer(Sys.getenv(
    "DIAS_VALIDACION_APP",
    unset = "2"
  )))
  if (is.na(valor) || valor < 0L) stop("DIAS_VALIDACION_APP debe ser un entero no negativo")
  valor
}

config_s3_app <- function() {
  requerido <- function(nombre) {
    valor <- trimws(Sys.getenv(nombre, unset = ""))
    if (!nzchar(valor)) stop("Falta configurar ", nombre, " para usar Cloudera S3")
    valor
  }

  prefijo <- gsub("^/+|/+$", "", Sys.getenv(
    "APP_S3_PREFIX",
    unset = "dario/modelo_com_app/data"
  ))
  if (!nzchar(prefijo)) stop("APP_S3_PREFIX no puede quedar vacio")

  cache <- Sys.getenv(
    "APP_S3_CACHE_PATH",
    unset = file.path(tempdir(), "modelo_com_app_s3")
  )

  list(
    connection = Sys.getenv("APP_S3_CONNECTION", unset = "S3 Object Store"),
    bucket = requerido("APP_S3_BUCKET"),
    prefix = prefijo,
    cache = normalizePath(cache, winslash = "/", mustWork = FALSE),
    refresh = identical(Sys.getenv("APP_S3_REFRESH", unset = "0"), "1")
  )
}

unir_key_s3_app <- function(...) {
  partes <- unlist(list(...), use.names = FALSE)
  partes <- gsub("^/+|/+$", "", partes)
  partes <- partes[nzchar(partes)]
  paste(partes, collapse = "/")
}

cliente_s3_app <- function() {
  if (!is.null(.app_fuente_cache$cliente_s3)) return(.app_fuente_cache$cliente_s3)
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    stop("El modo cloudera_s3 requiere el paquete R 'reticulate'")
  }

  cfg <- config_s3_app()
  reticulate::py_require(c("boto3", "raz-client>=1.1.0,<2"))
  cmldata <- reticulate::import("cml.data_v1", delay_load = FALSE)
  conexion <- cmldata$get_connection(cfg$connection)
  cliente <- conexion$get_base_connection()
  .app_fuente_cache$cliente_s3 <- cliente
  cliente
}

listar_objetos_s3_app <- function(prefijo_relativo = "") {
  cfg <- config_s3_app()
  cache_id <- unir_key_s3_app(cfg$prefix, prefijo_relativo)
  if (!is.null(.app_fuente_cache$listados) &&
      exists(cache_id, envir = .app_fuente_cache$listados, inherits = FALSE)) {
    return(get(cache_id, envir = .app_fuente_cache$listados, inherits = FALSE))
  }
  cliente <- cliente_s3_app()
  prefijo <- cache_id
  token <- NULL
  keys <- character()

  repeat {
    args <- list(Bucket = cfg$bucket, Prefix = prefijo)
    if (!is.null(token) && nzchar(token)) args$ContinuationToken <- token
    respuesta <- do.call(cliente$list_objects_v2, args)
    objetos <- respuesta$Contents
    if (!is.null(objetos) && length(objetos)) {
      keys <- c(keys, vapply(objetos, function(x) as.character(x$Key), character(1)))
    }
    if (!isTRUE(respuesta$IsTruncated)) break
    token <- as.character(respuesta$NextContinuationToken)
  }
  keys <- unique(keys)
  if (is.null(.app_fuente_cache$listados)) {
    .app_fuente_cache$listados <- new.env(parent = emptyenv())
  }
  assign(cache_id, keys, envir = .app_fuente_cache$listados)
  keys
}

ruta_cache_key_s3_app <- function(key) {
  cfg <- config_s3_app()
  prefijo_raiz <- paste0(cfg$prefix, "/")
  if (!startsWith(key, prefijo_raiz)) {
    stop("El objeto S3 esta fuera de APP_S3_PREFIX: ", key)
  }
  relativo <- substring(key, nchar(prefijo_raiz) + 1L)
  segmentos <- strsplit(relativo, "/", fixed = TRUE)[[1]]
  if (!length(segmentos) || any(segmentos %in% c("", ".", ".."))) {
    stop("Clave S3 no valida para la cache local: ", key)
  }
  file.path(cfg$cache, segmentos)
}

descargar_objeto_s3_app <- function(key) {
  cfg <- config_s3_app()
  destino <- ruta_cache_key_s3_app(key)
  if (is.null(.app_fuente_cache$descargados)) {
    .app_fuente_cache$descargados <- new.env(parent = emptyenv())
  }
  descargado_ahora <- exists(
    key,
    envir = .app_fuente_cache$descargados,
    inherits = FALSE
  )
  if (file.exists(destino) && (!cfg$refresh || descargado_ahora)) return(destino)

  dir.create(dirname(destino), recursive = TRUE, showWarnings = FALSE)
  temporal <- tempfile(pattern = ".descarga-", tmpdir = dirname(destino))
  on.exit(unlink(temporal, force = TRUE), add = TRUE)

  builtins <- reticulate::import_builtins()
  archivo_py <- builtins$open(normalizePath(
    temporal,
    winslash = "/",
    mustWork = FALSE
  ), "wb")
  tryCatch(
    cliente_s3_app()$download_fileobj(
      Bucket = cfg$bucket,
      Key = key,
      Fileobj = archivo_py
    ),
    finally = archivo_py$close()
  )
  if (!file.exists(temporal)) stop("No se descargo el objeto S3: ", key)
  if (file.exists(destino)) unlink(destino, force = TRUE)
  if (!file.rename(temporal, destino)) {
    stop("No se pudo publicar en cache el objeto S3: ", key)
  }
  assign(key, TRUE, envir = .app_fuente_cache$descargados)
  destino
}

materializar_prefijo_s3_app <- function(prefijo_relativo, keys = NULL,
                                        extension = NULL) {
  if (is.null(keys)) keys <- listar_objetos_s3_app(prefijo_relativo)
  keys <- keys[!endsWith(keys, "/")]
  if (!is.null(extension)) keys <- keys[endsWith(tolower(keys), tolower(extension))]
  if (!length(keys)) stop("No hay objetos S3 bajo el prefijo: ", prefijo_relativo)
  invisible(vapply(keys, descargar_objeto_s3_app, character(1)))
  segmentos <- strsplit(prefijo_relativo, "/", fixed = TRUE)[[1]]
  do.call(file.path, as.list(c(config_s3_app()$cache, segmentos)))
}

materializar_archivo_s3_app <- function(ruta_relativa) {
  key <- unir_key_s3_app(config_s3_app()$prefix, ruta_relativa)
  descargar_objeto_s3_app(key)
}

resolver_path_serie_app <- function() {
  if (!usar_s3_app()) {
    base <- Sys.getenv("APP_HISTORICO_PATH", unset = "data/historico")
    return(file.path(base, "serie_historica_com"))
  }
  materializar_prefijo_s3_app(
    "historico/serie_historica_com",
    extension = ".parquet"
  )
}

resolver_path_maestro_app <- function() {
  if (!usar_s3_app()) {
    return(Sys.getenv(
      "APP_CLUSTER_PATH",
      unset = "data/referencia/maestro_clusters"
    ))
  }
  materializar_prefijo_s3_app(
    "referencia/maestro_clusters",
    extension = ".parquet"
  )
}

resolver_path_barrios_app <- function() {
  if (!usar_s3_app()) {
    return(Sys.getenv(
      "APP_BARRIOS_PATH",
      unset = "data/referencia/barrios_mvd_23_pg.gpkg"
    ))
  }
  materializar_archivo_s3_app("referencia/barrios_mvd_23_pg.gpkg")
}

abrir_detalle_local_app <- function() {
  base <- Sys.getenv("APP_HISTORICO_PATH", unset = "data/historico")
  arrow::open_dataset(
    file.path(base, "detalle_cluster_dia"),
    partitioning = arrow::hive_partition(
      dia_objetivo = arrow::date32(),
      modelo_id = arrow::utf8()
    )
  )
}

partes_key_detalle_app <- function(key) {
  partes <- strsplit(key, "/", fixed = TRUE)[[1]]
  dia <- partes[startsWith(partes, "dia_objetivo=")]
  modelo <- partes[startsWith(partes, "modelo_id=")]
  if (!length(dia) || !length(modelo)) return(NULL)
  list(
    dia = sub("^dia_objetivo=", "", dia[[1]]),
    modelo = sub("^modelo_id=", "", modelo[[1]])
  )
}

listar_dias_detalle_s3_app <- function(modelo) {
  keys <- listar_objetos_s3_app("historico/detalle_cluster_dia")
  partes <- lapply(keys[endsWith(tolower(keys), ".parquet")], partes_key_detalle_app)
  dias <- vapply(partes, function(x) {
    if (is.null(x) || !identical(x$modelo, modelo)) return(NA_character_)
    x$dia
  }, character(1))
  sort(unique(dias[!is.na(dias)]))
}

cargar_detalle_dia_app <- function(fecha, modelo, ds_local = NULL) {
  fecha <- as.Date(fecha)
  if (!usar_s3_app()) {
    ds <- if (is.null(ds_local)) abrir_detalle_local_app() else ds_local
  } else {
    relativo <- paste0(
      "historico/detalle_cluster_dia/dia_objetivo=", fecha,
      "/modelo_id=", modelo
    )
    materializar_prefijo_s3_app(relativo, extension = ".parquet")
    ds <- arrow::open_dataset(
      file.path(config_s3_app()$cache, "historico", "detalle_cluster_dia"),
      partitioning = arrow::hive_partition(
        dia_objetivo = arrow::date32(),
        modelo_id = arrow::utf8()
      )
    )
  }

  ds |>
    dplyr::filter(
      dia_objetivo == !!fecha,
      modelo_id == !!modelo
    ) |>
    dplyr::collect() |>
    data.table::as.data.table()
}

cargar_predicciones_operacion_app <- function() {
  if (!usar_s3_app()) {
    path_base <- resolver_path_datos_app()
    ds <- arrow::open_dataset(
      file.path(path_base, "predicciones_operativas_cluster_dia"),
      format = "parquet"
    )
    resumen <- ds |>
      dplyr::summarise(dia_operativo = max(dia_objetivo, na.rm = TRUE)) |>
      dplyr::collect()
    dia <- as.Date(resumen$dia_operativo[[1]])
  } else {
    path_control <- materializar_prefijo_s3_app(
      "operacional/control_scoring",
      extension = ".parquet"
    )
    control <- leer_dataset_app(path_control)
    if (!nrow(control) || !"dia_objetivo" %in% names(control)) {
      stop("control_scoring no permite determinar el ultimo dia operativo")
    }
    dia <- max(as.Date(control$dia_objetivo), na.rm = TRUE)
    anio_mes <- format(dia, "%Y%m")
    prefijo_pred <- "operacional/predicciones_operativas_cluster_dia"
    keys <- listar_objetos_s3_app(prefijo_pred)
    keys <- keys[
      grepl(paste0("/anio_mes=", anio_mes, "/"), keys, fixed = TRUE) &
        endsWith(tolower(keys), ".parquet")
    ]
    path_pred <- materializar_prefijo_s3_app(prefijo_pred, keys = keys)
    ds <- arrow::open_dataset(path_pred, format = "parquet")
  }

  pred <- ds |>
    dplyr::filter(dia_objetivo == !!dia) |>
    dplyr::collect() |>
    data.table::as.data.table()
  pred[, dia_objetivo := data.table::as.IDate(dia_objetivo)]
  list(predicciones = pred, dia_operativo = data.table::as.IDate(dia))
}
