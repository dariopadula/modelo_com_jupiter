# Arranque de validacion: solo configuracion, sin lecturas de datos ni escritura.
all_args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", all_args, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "R/acceso/configuracion.R"), local = TRUE)
source(file.path(root, "R/registro/contratos.R"), local = TRUE)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L) stop("Uso: validar_base.R [configuracion.dcf]")
cfg <- rf_config(root, if (length(args)) args[[1L]] else NULL)
cat("R02_BASE_OK\n")
cat("Entorno:", cfg$values[["RF_ENVIRONMENT"]], "\n")
cat("Entrada:", cfg$values[["INGESTA_INPUT_BACKEND"]], "| Persistencia:", cfg$values[["PIPELINE_STORAGE_BACKEND"]],
  "| App:", cfg$values[["APP_DATA_SOURCE"]], "\n")
