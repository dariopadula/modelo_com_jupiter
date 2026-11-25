# Construye derivados COM propios desde insumos historicos preparados.  Entrada:
# runtime/r04_com/insumos.rds. Salidas: asignaciones, base y features R04.
all_args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", all_args, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
.libPaths(c("C:/Users/dario/AppData/Local/R/win-library/4.5", .libPaths()))
source(file.path(root, "R/ingesta/cargar_componentes.R"))
source(file.path(root, "R/acceso/configuracion.R"))
rf_load_com_components(root)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 2L) stop("Uso: preparar_datos_com.R [insumos_relativos.rds] [directorio_salida_relativo]")
input_relative <- if (length(args) >= 1L) args[[1L]] else "runtime/r04_com/insumos.rds"
output_relative <- if (length(args) >= 2L) args[[2L]] else "runtime/r04_com"
input <- rf_config(root, env = c(RF_RUNTIME_PATH = input_relative))$values[["RF_RUNTIME_PATH"]]
path <- rf_config(root, env = c(RF_RUNTIME_PATH = output_relative))$values[["RF_RUNTIME_PATH"]]
if (!file.exists(input)) stop("Faltan insumos historicos propios de R04")
inputs <- readRDS(input)
result <- if (!is.null(inputs$raw_levante)) {
  rf_process_raw_com(inputs)
} else {
  rf_process_prepared_com(inputs)
}
dir.create(path, recursive = TRUE, showWarnings = FALSE)
saveRDS(result, file.path(path, "derivados.rds"))
cat("COM_DATOS_OK:", nrow(result$features), "filas de features; cierre", result$closure_status,
  "\n")
