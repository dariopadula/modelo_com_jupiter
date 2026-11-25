# Importa un snapshot real para comprobar productos/interfaz, sin recalcular scores.
# No promueve candidatos R06/R07 ni certifica cierres nuevos. Uso: <raiz_original> <directorio_nuevo> [todas]
arguments <- commandArgs(trailingOnly = TRUE)
if (!length(arguments) %in% c(2L, 3L)) {
  stop("Uso: preparar_piloto_app_r08.R <raiz_original> <directorio_nuevo> [todas]")
}
script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/")
source(file.path(root, "R/configuracion/runtime_r07.R"), encoding = "UTF-8")
rf_init_r07()
library(data.table)
legacy <- normalizePath(arguments[[1L]], winslash = "/", mustWork = TRUE)
output <- arguments[[2L]]
if (file.exists(output) || dir.exists(output)) {
  stop("La salida ya existe; elegir un destino nuevo")
}
all_dates <- length(arguments) == 3L && identical(arguments[[3L]], "todas")
dates <- as.Date(c("2026-03-31", "2026-05-24"))
source_path <- file.path(legacy, "app_operativa_v2/data")
scores <- arrow::open_dataset(file.path(source_path, "operacional/predicciones_operativas_cluster_dia"))
if (!all_dates) {
  scores <- dplyr::filter(scores, dia_objetivo %in% dates)
}
scores <- dplyr::filter(scores, modelo_id %in% c("com_reclamo", "zl_problema"))
series <- arrow::open_dataset(file.path(source_path, "historico/serie_historica_com"))
if (!all_dates) {
  series <- dplyr::filter(series, dia_objetivo %in% dates)
}
series <- as.data.table(as.data.frame(
  dplyr::collect(dplyr::filter(series, escenario == "P3_compacto"))
))
master <- as.data.table(as.data.frame(dplyr::collect(
  arrow::open_dataset(file.path(source_path, "referencia/maestro_clusters"))
)))
dir.create(output, recursive = TRUE)
scores_path <- file.path(output, "scores")
arrow::write_dataset(scores, scores_path, format = "parquet", compression = "zstd",
  partitioning = c("dia_objetivo", "modelo_id"))
shape_path <- file.path(output, "barrios.gpkg")
if (!file.copy(file.path(source_path, "referencia/barrios_mvd_23_pg.gpkg"), shape_path)) {
  stop("Fallo la importacion de la referencia territorial")
}
package <- list(scores_path = normalizePath(scores_path, winslash = "/"), series = series,
  master = master, shape_path = normalizePath(shape_path, winslash = "/"), days_validation = 2L,
  provenance = list(origin = "snapshot_importado_app_vigente", scores_recomputed = FALSE,
    candidate_models_promoted = FALSE, snapshot_scope = if (all_dates) "historia_publicada" else "dos_fechas_reales"),
  label = if (all_dates) "Reconstrucción — snapshot histórico importado; modelos candidatos sin promover" else
    "Reconstrucción — piloto real: 31/03 y 24/05/2026; snapshot importado, historia parcial")
saveRDS(package, file.path(output, "entrada.rds"))
cat("R08_INPUT_OK: scope=", package$provenance$snapshot_scope, " series_rows=", nrow(series), "\n", sep = "")
