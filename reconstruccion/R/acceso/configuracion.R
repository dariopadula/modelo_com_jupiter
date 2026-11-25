# Configuracion independiente del codigo original. No conecta ni publica.

# Valida y resuelve la raiz propia de reconstruccion.  Entrada: ruta existente. Salida:
# ruta absoluta; falla si no es una raiz valida.

# Valida y resuelve la raiz propia de reconstruccion.  Entrada: ruta existente. Salida:
# ruta absoluta; falla si no es una raiz valida.
rf_root <- function(path) {
  root <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (!file.exists(file.path(root, "config", "local.dcf.example")) || !dir.exists(file.path(root,
    "cerebro_rf")))
    stop("Raiz de reconstruccion invalida")
  root
}


# Construye configuracion validada sin conectar a servicios.  Entradas: raiz, archivo
# DCF opcional y entorno. Salida: objeto rf_config sin credenciales.

# Construye configuracion validada sin conectar a servicios.  Entradas: raiz, archivo
# DCF opcional y entorno. Salida: objeto rf_config sin credenciales.
rf_config <- function(root, file = NULL, env = Sys.getenv()) {
  root <- rf_root(root)
  defaults <- c(RF_ENVIRONMENT = "local", RF_RUNTIME_PATH = "runtime", INGESTA_INPUT_BACKEND = "local",
    PIPELINE_STORAGE_BACKEND = "local", APP_DATA_SOURCE = "local", RF_EXTRACTOR = "entrega",
    PIPELINE_S3_CONNECTION = "S3 Object Store", PIPELINE_S3_BUCKET = "", INGESTA_S3_PREFIX = "",
    INGESTA_S3_MANIFEST_KEY = "", PIPELINE_S3_PREFIX = "", APP_S3_CONNECTION = "S3 Object Store",
    APP_S3_BUCKET = "", APP_S3_PREFIX = "", IMPALA_JDBC_JAR = "", IMPALA_JDBC_URL = "",
    RF_TIMEZONE = "America/Montevideo")
  values <- defaults
  if (!is.null(file)) {
    d <- read.dcf(file)
    if (nrow(d) != 1L)
      stop("La configuracion debe contener un registro DCF")
    if (any(!colnames(d) %in% names(defaults)))
      stop("Campo de configuracion desconocido")
    values[colnames(d)] <- d[1L, ]
  }
  present <- intersect(names(defaults), names(env))
  values[present] <- env[present]
  values <- trimws(values)

  # Comprueba que un selector pertenezca a sus opciones permitidas.  Entradas: clave y
  # opciones. Salida: valor validado o error.

  # Comprueba que un selector pertenezca a sus opciones permitidas.  Entradas: clave y
  # opciones. Salida: valor validado o error.
  pick <- function(key, options) {
    v <- values[[key]]
    if (!v %in% options)
      stop("Valor invalido en ", key)
    v
  }
  pick("RF_ENVIRONMENT", c("local", "cloudera"))
  pick("RF_EXTRACTOR", c("entrega", "impala"))
  if (values[["RF_TIMEZONE"]] != "America/Montevideo")
    stop("Zona horaria incompatible")
  for (key in c("INGESTA_INPUT_BACKEND", "PIPELINE_STORAGE_BACKEND", "APP_DATA_SOURCE")) {
    if (values[[key]] %in% c("s3", "cloudera"))
      values[[key]] <- "cloudera_s3"
    pick(key, c("local", "cloudera_s3"))
  }

  # Exige valores definitivos para las claves activas.  Entrada: nombres de claves.
  # Salida: ninguna; falla ante vacios o placeholders.

  # Exige valores definitivos para las claves activas.  Entrada: nombres de claves.
  # Salida: ninguna; falla ante vacios o placeholders.
  required <- function(keys) {
    for (key in keys) if (!nzchar(values[[key]]) || grepl("<|>", values[[key]])) {
      stop("Falta valor definitivo para ", key)
    }
  }

  # Valida que un prefijo de objetos no contenga rutas inseguras.  Entrada: clave de
  # configuracion. Salida: ninguna o error.

  # Valida que un prefijo de objetos no contenga rutas inseguras.  Entrada: clave de
  # configuracion. Salida: ninguna o error.
  prefix <- function(key) {
    v <- values[[key]]
    if (grepl("(^/|\\\\|(^|/)\\.\\.(/|$)|//)", v))
      stop("Prefijo inseguro en ", key)
  }
  if (any(values[c("INGESTA_INPUT_BACKEND", "PIPELINE_STORAGE_BACKEND")] == "cloudera_s3")) {
    required(c("PIPELINE_S3_CONNECTION", "PIPELINE_S3_BUCKET"))
  }
  if (values[["INGESTA_INPUT_BACKEND"]] == "cloudera_s3") {
    required(c("INGESTA_S3_PREFIX", "INGESTA_S3_MANIFEST_KEY"))
    prefix("INGESTA_S3_PREFIX")
    prefix("INGESTA_S3_MANIFEST_KEY")
    if (!startsWith(values[["INGESTA_S3_MANIFEST_KEY"]], paste0(sub("/+$", "", values[["INGESTA_S3_PREFIX"]]),
      "/"))) {
      stop("El manifiesto debe quedar dentro del prefijo de entregas")
    }
  }
  if (values[["PIPELINE_STORAGE_BACKEND"]] == "cloudera_s3") {
    required("PIPELINE_S3_PREFIX")
    prefix("PIPELINE_S3_PREFIX")
  }
  if (values[["APP_DATA_SOURCE"]] == "cloudera_s3") {
    required(c("APP_S3_CONNECTION", "APP_S3_BUCKET", "APP_S3_PREFIX"))
    prefix("APP_S3_PREFIX")
  }
  if (values[["RF_EXTRACTOR"]] == "impala") {
    required(c("IMPALA_JDBC_JAR", "IMPALA_JDBC_URL"))
    if (!file.exists(values[["IMPALA_JDBC_JAR"]]))
      stop("Driver Impala no encontrado")
    # Secretos se comprueban sin incorporarlos al objeto ni a mensajes.
    if (!all(c("IMPALA_USER", "IMPALA_PASSWORD") %in% names(env)) || any(!nzchar(env[c("IMPALA_USER",
      "IMPALA_PASSWORD")])))
      stop("Faltan credenciales Impala en entorno")
  }
  local_path <- values[["RF_RUNTIME_PATH"]]
  if (!nzchar(local_path) || grepl("^(/|[A-Za-z]:|\\\\)", local_path))
    stop("RF_RUNTIME_PATH debe ser relativa a la raiz nueva")
  parts <- strsplit(gsub("\\\\", "/", local_path), "/", fixed = TRUE)[[1L]]
  if (any(parts == ".."))
    stop("RF_RUNTIME_PATH no puede salir de la raiz nueva")
  values[["RF_RUNTIME_PATH"]] <- file.path(root, local_path)
  structure(list(root = root, values = values), class = "rf_config")
}
