# Copia productos ready a una version nueva. La activacion requiere argumento explicito.
# Uso: <publicacion_R08> <almacen_local> <version> [activar]. S3 usa el entorno configurado.
arguments <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "R/configuracion/runtime_r07.R"))
rf_init_r07()
source(file.path(root, "R/acceso/cargar_acceso.R"))
rf_load_access(root)
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(3L, 4L) || (length(args) == 4L && args[[4L]] != "activar")) {
  stop("Uso: publicar_productos.R <publicacion_R08> <almacen_local> <version> [activar]")
}
config <- rf_config(root)
store <- rf_store(config, "pipeline", args[[2L]])
rf_publish_version(args[[1L]], store, args[[3L]])
if (length(args) == 4L) rf_activate_version(store, args[[3L]], file.path(config$values[["RF_RUNTIME_PATH"]], "cache_publicador"))
cat("R09_PUBLISH_OK: version=", args[[3L]], " activated=", length(args) == 4L, " backend=", store$backend, "\n", sep = "")

