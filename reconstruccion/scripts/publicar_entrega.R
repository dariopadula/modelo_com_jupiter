# Publica una entrega contractual en el backend de entrada, con manifiesto al final.
# Uso: <entrega_local> <almacen_local>. S3 usa el prefijo de entrega configurado, nuevo y aislado.
arguments <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "R/configuracion/runtime_r07.R"))
rf_init_r07()
source(file.path(root, "R/acceso/cargar_acceso.R"))
rf_load_access(root)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Uso: publicar_entrega.R <entrega_local> <almacen_local>")
config <- rf_config(root)
store <- rf_store(config, "input", args[[2L]])
key <- if (store$backend == "local") "manifest.json" else
  substring(config$values[["INGESTA_S3_MANIFEST_KEY"]], nchar(store$prefix) + 2L)
id <- rf_publish_delivery(args[[1L]], store, key, file.path(config$values[["RF_RUNTIME_PATH"]], "cache_entregas"))
cat("R09_DELIVERY_PUBLISHED_OK: delivery=", id, "\n", sep = "")
