# Puntua bases segmento/dia propias con A0/P3 fijo fuera del periodo de entrenamiento.
# Uso: predecir_agregado.R <base_o_paquete.rds> <bundle.rds> <salida_nueva.rds> [fecha_objetivo]
arguments <- commandArgs(trailingOnly = TRUE)
if (!length(arguments) %in% c(3L, 4L)) {
  stop("Uso: predecir_agregado.R <entrada.rds> <bundle.rds> <salida_nueva.rds> [fecha_objetivo]")
}
script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/")
source(file.path(root, "R/configuracion/runtime_r07.R"), encoding = "UTF-8")
rf_init_r07()
library(data.table)
source(file.path(root, "R/modelos/agregado_a0_p3.R"), encoding = "UTF-8")
if (file.exists(arguments[[3L]])) {
  stop("La salida ya existe; elegir una ruta nueva")
}
input <- readRDS(arguments[[1L]])
base <- if (!is.null(input$p3_base)) input$p3_base else input$base
base <- as.data.table(base)
if (length(arguments) == 4L) {
  requested_day <- as.IDate(arguments[[4L]])
  if (is.na(requested_day)) {
    stop("Fecha objetivo invalida")
  }
  base <- base[as.IDate(dia_objetivo) == requested_day]
}
bundle <- readRDS(arguments[[2L]])
result <- rf_score_aggregate(base, bundle)
dir.create(dirname(arguments[[3L]]), recursive = TRUE, showWarnings = FALSE)
saveRDS(result, arguments[[3L]])
cat("R07_PREDICTION_OK: segmento=", nrow(result$segmento), " barrio=", nrow(result$barrio),
  " dias=", nrow(result$montevideo), "\n", sep = "")
