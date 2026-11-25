# Inicia la app desde una publicacion directa R08 o un puntero local/S3 R09.
# Entrada: RF_APP_PUBLICATION, RF_APP_STORE, APP_DATA_SOURCE y APP_PORT en entorno.
# Salida: servidor Shiny en primer plano; Ctrl+C lo detiene.
arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)

source(file.path(root, "R/configuracion/runtime_r07.R"), encoding = "UTF-8")
rf_init_r07()

required_packages <- c("shiny", "bslib", "leaflet", "DT", "plotly", "sf", "arrow", "data.table", "dplyr", "jsonlite")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages)) {
  stop("Faltan paquetes instalados: ", paste(missing_packages, collapse = ", "))
}

source(file.path(root, "R/acceso/configuracion.R"), encoding = "UTF-8")
config <- rf_config(root)
versioned <- config$values[["APP_DATA_SOURCE"]] == "cloudera_s3" || nzchar(Sys.getenv("RF_APP_STORE", ""))
publication_path <- Sys.getenv("RF_APP_PUBLICATION", unset = "")
if (!versioned) {
  if (!nzchar(publication_path)) {
    publication_path <- file.path(root, "runtime/r08_app/publicacion_piloto")
  }
  publication_path <- normalizePath(publication_path, winslash = "/", mustWork = TRUE)
  manifest_path <- file.path(publication_path, "publicacion.rds")
  if (!file.exists(manifest_path)) {
    stop("Falta el manifiesto de la publicacion: ", manifest_path)
  }
  manifest <- readRDS(manifest_path)
  if (!identical(manifest$status, "ready")) {
    stop("La publicacion no esta marcada como lista: ", publication_path)
  }
  Sys.setenv(RF_APP_PUBLICATION = publication_path)
} else {
  publication_path <- paste0("puntero versionado (", config$values[["APP_DATA_SOURCE"]], ")")
}

port <- suppressWarnings(as.integer(Sys.getenv("CDSW_APP_PORT", unset = Sys.getenv("APP_PORT", "3843"))))
if (is.na(port) || port < 1024L || port > 65535L) {
  stop("APP_PORT invalido; indicar un puerto entre 1024 y 65535")
}

open_browser <- Sys.getenv("RF_OPEN_BROWSER", "1") == "1"
cat("Publicacion: ", publication_path, "\n", sep = "")
cat("Direccion: http://127.0.0.1:", port, "\n", sep = "")
cat("Mantene esta consola abierta. Para detener la app: Ctrl+C.\n")
flush.console()

# app.R carga explicitamente sus modulos; evitar una segunda carga automatica
# de la carpeta R en el entorno aislado que Shiny crea para la aplicacion.
options(shiny.autoload.r = FALSE)
shiny::runApp(
  file.path(root, "app"),
  host = "127.0.0.1",
  port = port,
  launch.browser = open_browser
)
