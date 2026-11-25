# Lee fuentes_v2 por backend y guarda rutas/marcas propias; no prepara ni puntua datos.
arguments <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "R/configuracion/runtime_r07.R"))
rf_init_r07()
source(file.path(root, "R/acceso/cargar_acceso.R"))
rf_load_access(root)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("Uso: materializar_entrega.R <manifest_key> <raiz_local_entrega> <salida_nueva.rds>")
if (file.exists(args[[3L]])) stop("La salida ya existe")
config <- rf_config(root)
store <- rf_store(config, "input", args[[2L]])
key <- args[[1L]]
if (store$backend == "cloudera_s3") {
  key <- substring(config$values[["INGESTA_S3_MANIFEST_KEY"]], nchar(store$prefix) + 2L)
}
delivery <- rf_materialize_delivery(store, key, file.path(config$values[["RF_RUNTIME_PATH"]], "cache_entregas"))
dir.create(dirname(args[[3L]]), recursive = TRUE, showWarnings = FALSE)
saveRDS(delivery, args[[3L]])
cat("R09_DELIVERY_OK: delivery=", delivery$delivery_id, " backend=", store$backend, "\n", sep = "")

