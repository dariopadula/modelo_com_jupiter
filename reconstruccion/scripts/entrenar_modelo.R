# Ejecuta un entrenamiento seleccionado sobre un paquete RDS preparado.
# Uso: Rscript entrenar_modelo.R <entrada.rds> <directorio_salida_nuevo>
# No modifica el modelo activo ni dispara ingesta, scoring operativo o publicacion.

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 2L) {
  stop("Uso: entrenar_modelo.R <entrada.rds> <directorio_salida_nuevo>")
}
script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/")
library_version <- paste0(R.version$major, ".", sub("\\..*$", "", R.version$minor))
user_library <- Sys.getenv("RF_R_LIBRARY", unset = "")
if (!nzchar(user_library) && nzchar(Sys.getenv("USERPROFILE"))) {
  user_library <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "R", "win-library", library_version)
}
if (dir.exists(user_library)) {
  .libPaths(c(user_library, .libPaths()))
}
library(data.table)
source(file.path(root, "R/features/com_receta.R"))
source(file.path(root, "R/features/zl_receta.R"))
source(file.path(root, "R/entrenamiento/com_zl.R"))

input_path <- normalizePath(arguments[[1L]], winslash = "/", mustWork = TRUE)
output_path <- normalizePath(arguments[[2L]], winslash = "/", mustWork = FALSE)
if (file.exists(output_path) || dir.exists(output_path)) {
  stop("El destino ya existe; elegir un directorio nuevo")
}
package <- readRDS(input_path)
if (!all(c("family", "data", "reference", "provenance") %in% names(package))) {
  stop("El paquete no contiene family, data, reference y provenance")
}
elapsed <- system.time(result <- rf_train_selected(package$data, package$family, package$reference))
result$provenance <- package$provenance
result$input_md5 <- unname(tools::md5sum(input_path))
result$candidate_id <- paste0(package$family, "_r06_", substr(result$input_md5, 1L, 12L),
  "_s", result$seed)
result$model$candidate_id <- result$candidate_id
result$model$training_status <- result$status
result$model$training_seed <- result$seed
result$model$input_md5 <- result$input_md5
result$seconds <- unname(elapsed[["elapsed"]])
result$R <- R.version.string
result$packages <- lapply(c("data.table", if (package$family == "zl") "xgboost"), function(name) {
  list(package = name, version = as.character(utils::packageVersion(name)))
})
if (!dir.exists(dirname(output_path))) {
  dir.create(dirname(output_path), recursive = TRUE)
}
if (!dir.create(output_path)) {
  stop("No se pudo reservar el directorio de salida nuevo")
}
saveRDS(result, file.path(output_path, "resultado.rds"))
saveRDS(result$model, file.path(output_path, "modelo_candidato.rds"))
data.table::fwrite(result$metrics, file.path(output_path, "metricas.csv"))
data.table::fwrite(result$predictions[, .(version_cluster, cluster_id, dia, split)],
  file.path(output_path, "splits.csv"))
print(result$metrics)
cat("R06_TRAINING_OK: family=", package$family, " status=candidato_no_promovido seconds=",
  result$seconds, " output=", output_path, "\n", sep = "")
