# Ejecuta la inferencia COM sobre la muestra propia ya preparada.  Entradas: historia,
# bundle y metadatos importados dentro de runtime/r03_com/.  Salida:
# producto_com_actual.rds; no modifica la referencia congelada.
all_args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", all_args, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
.libPaths(c("C:/Users/dario/AppData/Local/R/win-library/4.5", .libPaths()))
source(file.path(root, "R/features/com_receta.R"))
source(file.path(root, "R/modelos/com_logistico.R"))
source(file.path(root, "R/registro/contratos.R"))

path <- file.path(root, "runtime/r03_com")
required <- c("entrada.rds", "modelo_com.rds", "producto_com.rds")
if (!all(file.exists(file.path(path, required)))) {
  stop("Falta preparar la muestra COM propia antes de ejecutar inferencia")
}

entry <- readRDS(file.path(path, "entrada.rds"))[c("day", "universe_n")]
validation_path <- file.path(root, "config/validacion_r04.json")
if (!file.exists(validation_path)) {
  stop("Falta validar los derivados R04 con tests/test_datos_com_r04.R")
}
validation <- jsonlite::read_json(validation_path, simplifyVector = TRUE)
derived_path <- file.path(root, "runtime/r04_com/derivados.rds")
con <- file(derived_path, "rb")
hash <- unname(unclass(as.character(openssl::sha256(con))))
close(con)
if (!identical(validation$status, "validado_bloque_historico") ||
    !identical(hash, validation$derivados_sha256)) {
  stop("Derivados R04 sin validacion vigente; ejecutar tests/test_datos_com_r04.R")
}
entry$history <- readRDS(derived_path)$features
features_source <- "r04_fuentes_preparadas_snapshot_historico"
model <- readRDS(file.path(path, "modelo_com.rds"))
# En R03 los observados y coordenadas son una instantanea importada, no recalculada.
product <- readRDS(file.path(path, "producto_com.rds"))
predictions <- rf_score_com(entry$history, model, entry$day, entry$universe_n)
keys <- c("cluster_id", "dia_objetivo", "modelo_id", "version_modelo")
rf_prediction_contract(product)
if (nrow(predictions) != nrow(product) || !all(vapply(keys, function(key) {
  identical(as.character(predictions[[key]]), as.character(product[[key]]))
}, logical(1)))) {
  stop("La inferencia no corresponde al bloque preparado")
}

computed <- c("pred_prob", "ranking_dia", "percentil_riesgo", "top_1", "top_5", "top_10",
  "top_20")
product[computed] <- predictions[computed]
product$features_source <- features_source
rf_prediction_contract(product)
saveRDS(product, file.path(path, "producto_com_actual.rds"))
cat("COM_PREDICCIONES_OK:", nrow(product), "clusters para", as.character(entry$day), "\n")
cat("Features:", features_source, "\n")
