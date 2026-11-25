# Activa una version existente o restaura el respaldo; no recalcula ni copia modelos.
arguments <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "R/configuracion/runtime_r07.R"))
rf_init_r07()
source(file.path(root, "R/acceso/cargar_acceso.R"))
rf_load_access(root)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Uso: activar_publicacion.R <almacen_local> <version|restaurar>")
config <- rf_config(root)
store <- rf_store(config, "pipeline", args[[1L]])
cache <- file.path(config$values[["RF_RUNTIME_PATH"]], "cache_publicador")
if (args[[2L]] == "restaurar") {
  id <- rf_restore_publication(store, cache)
} else {
  id <- rf_activate_version(store, args[[2L]], cache)
}
cat("R09_ACTIVATE_OK: version=", id, "\n", sep = "")

