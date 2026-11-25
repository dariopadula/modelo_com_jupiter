# Extrae meses explicitos de Impala; el pedido declara cierres y disponibilidad.
arguments <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "R/configuracion/runtime_r07.R"))
rf_init_r07()
source(file.path(root, "R/acceso/cargar_acceso.R"))
rf_load_access(root)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Uso: extraer_fuentes.R <pedido.json> <directorio_nuevo>")
request <- jsonlite::read_json(args[[1L]], simplifyVector = TRUE)
manifest <- rf_extract_impala(request, args[[2L]], rf_config(root))
cat("R09_EXTRACT_OK: delivery=", manifest$delivery_id, "\n", sep = "")

