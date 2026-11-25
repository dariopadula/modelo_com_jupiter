# Ejecuta OOF A0 y seleccion/refit P3 sobre bases propias; genera candidato aislado.
# Uso: entrenar_agregado.R <bases.rds> <directorio_salida_nuevo>
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 2L || file.exists(arguments[[2L]]) || dir.exists(arguments[[2L]])) {
  stop("Uso: entrenar_agregado.R <bases.rds> <directorio_salida_nuevo>; no sobrescribir")
}
script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/")
source(file.path(root, "R/configuracion/runtime_r07.R"), encoding = "UTF-8")
rf_init_r07()
library(data.table)
source(file.path(root, "R/modelos/agregado_a0_p3.R"), encoding = "UTF-8")
source(file.path(root, "R/entrenamiento/agregado_a0_p3.R"), encoding = "UTF-8")
input <- readRDS(arguments[[1L]])
elapsed <- system.time(result <- rf_train_aggregate(input))
result$seconds <- unname(elapsed[["elapsed"]])
result$provenance <- input$provenance
result$input_md5 <- unname(tools::md5sum(arguments[[1L]]))
result$bundle$candidate_id <- paste0("a0_p3_r07_", substr(result$input_md5, 1L, 12L))
result$R <- R.version.string
result$packages <- lapply(c("data.table", "mgcv", "xgboost"), function(name) {
  list(package = name, version = as.character(utils::packageVersion(name)))
})
dir.create(dirname(arguments[[2L]]), recursive = TRUE, showWarnings = FALSE)
if (!dir.create(arguments[[2L]])) {
  stop("No se pudo reservar el destino nuevo")
}
saveRDS(result, file.path(arguments[[2L]], "resultado.rds"))
saveRDS(result$bundle, file.path(arguments[[2L]], "bundle_candidato.rds"))
fwrite(result$metrics, file.path(arguments[[2L]], "metricas.csv"))
fwrite(result$oof, file.path(arguments[[2L]], "auditoria_oof.csv"))
fwrite(result$predictions$montevideo, file.path(arguments[[2L]], "predicciones_diarias.csv"))
fwrite(result$predictions$barrio, file.path(arguments[[2L]], "predicciones_barrio_dia.csv"))
print(result$metrics)
cat("R07_TRAINING_OK: status=candidato_no_promovido best_iteration=", result$bundle$best_iteration,
  " seconds=", result$seconds, "\n", sep = "")
