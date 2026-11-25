# Construye bases A0/P3 propias desde un paquete canonico importado o preparado.
# Uso: preparar_agregado.R <insumos.rds> <salida_nueva.rds>
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 2L || file.exists(arguments[[2L]])) {
  stop("Uso: preparar_agregado.R <insumos.rds> <salida_nueva.rds>; no sobrescribir")
}
script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/")
source(file.path(root, "R/configuracion/runtime_r07.R"), encoding = "UTF-8")
rf_init_r07()
library(data.table)
source(file.path(root, "R/features/agregado_receta.R"), encoding = "UTF-8")
input <- readRDS(arguments[[1L]])
result <- rf_build_aggregate(input$features, input$geography, input$calendar, input$holidays)
result$provenance <- input$provenance
result$input_md5 <- unname(tools::md5sum(arguments[[1L]]))
if (!nrow(result$p3_base) || !nrow(result$a0_base)) {
  stop("La preparacion no genero bases A0/P3 utilizables")
}
dir.create(dirname(arguments[[2L]]), recursive = TRUE, showWarnings = FALSE)
saveRDS(result, arguments[[2L]])
cat("R07_FEATURES_OK: a0=", nrow(result$a0_base), " p3=", nrow(result$p3_base), "\n", sep = "")
