# Construye una publicacion propia a partir de scores y series calculados previamente.
# Uso: construir_productos_app.R <paquete_entrada.rds> <directorio_publicacion_nuevo>
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 2L) {
  stop("Uso: construir_productos_app.R <paquete_entrada.rds> <directorio_publicacion_nuevo>")
}
script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/")
source(file.path(root, "R/configuracion/runtime_r07.R"), encoding = "UTF-8")
rf_init_r07()
library(data.table)
source(file.path(root, "R/publicacion/productos_app.R"), encoding = "UTF-8")
package <- readRDS(arguments[[1L]])
result <- rf_build_app_products(package, arguments[[2L]])
cat("R08_PRODUCTS_OK: publication=", result$publication_id, " days=", length(result$dates),
  " rows=", result$detail_rows, " operational_day=", result$operational_day, "\n", sep = "")
