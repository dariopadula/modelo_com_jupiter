# Ejecuta un bloque COM incremental desde un paquete de entrada aislado.
# Entrada: RDS con features, bundle, estado inicial, marcas y predicciones previas.
# Salida: RDS nuevo con predicciones, estado y controles; no sobrescribe archivos.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 2L) {
  stop("Uso: scoring_com_incremental.R <entrada.rds> <salida_nueva.rds>")
}

script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
project_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
input_path <- normalizePath(arguments[[1L]], winslash = "/", mustWork = TRUE)
output_path <- normalizePath(arguments[[2L]], winslash = "/", mustWork = FALSE)
if (file.exists(output_path)) {
  stop("La salida ya existe; elegir un destino nuevo")
}

library_version <- paste0(R.version$major, ".", sub("\\..*$", "", R.version$minor))
user_library <- Sys.getenv("RF_R_LIBRARY", unset = Sys.getenv("R_LIBS_USER", unset = ""))
if ((!nzchar(user_library) || !dir.exists(user_library)) && identical(Sys.info()[["sysname"]], "Windows") && nzchar(Sys.getenv("USERPROFILE"))) {
  user_library <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "R", "win-library", library_version)
}
if (!is.null(user_library) && dir.exists(user_library)) {
  .libPaths(c(user_library, .libPaths()))
}
source(file.path(project_root, "R/features/com_receta.R"))
source(file.path(project_root, "R/modelos/com_logistico.R"))
source(file.path(project_root, "R/operacion/estado_com.R"))
source(file.path(project_root, "R/operacion/scoring_incremental_com.R"))

input <- readRDS(input_path)
required <- c("features", "model", "state", "marks", "through_day")
if (!all(required %in% names(input))) {
  stop("El paquete de entrada COM esta incompleto")
}
result <- rf_run_com_incremental(
  features = input$features,
  model = input$model,
  state = input$state,
  predictions = input$predictions,
  marks = input$marks,
  through_day = input$through_day,
  universe_n = input$universe_n
)

output_directory <- dirname(output_path)
dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
temporary_path <- tempfile("scoring_com_", tmpdir = output_directory, fileext = ".rds")
saveRDS(result, temporary_path)
if (!file.rename(temporary_path, output_path)) {
  unlink(temporary_path)
  stop("No se pudo completar la escritura atomica del resultado")
}
cat("SCORING_COM_INCREMENTAL_OK:", nrow(result$predictions), "predicciones; estado hasta", as.character(result$state_day), "\n")
