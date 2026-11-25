# Compara features actuales y resumen publicado de mayo, sin alterar referencias.
all_args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", all_args, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Indicar raiz original")
old <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
.libPaths(c("C:/Users/dario/AppData/Local/R/win-library/4.5", .libPaths()))
source(file.path(root, "R/features/com_receta.R"))
source(file.path(root, "R/modelos/com_logistico.R"))
day <- as.Date("2026-05-24")
start <- day - 180L
published <- arrow::open_dataset(file.path(old, "app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia"))
published <- as.data.frame(dplyr::collect(dplyr::filter(published, modelo_id == "com_reclamo",
  dia_objetivo == !!day)))
published <- published[order(published$ranking_dia), ]
ref <- head(published, 50L)
ids <- ref$cluster_id
ds <- arrow::open_dataset(file.path(old, "data/processed/modelo_cluster_dia/features_cluster_dia"))
history <- dplyr::collect(dplyr::filter(ds, cluster_id %in% !!ids, dia >= !!start, dia <=
  !!day, version_cluster == "v2026_05_25", cluster_existente_dia == TRUE))
prepared <- agregar_features_logistico_reducido(aplicar_rezago_historia_reclamos(history,
  2L))
prepared <- prepared[dia == data.table::as.IDate(day)]
prepared <- prepared[match(ref$cluster_id, prepared$cluster_id)]
fields <- c("n_reclamos_lag1", "n_reclamos_sum_7d", "n_reclamos_sum_30d", "dias_desde_ultimo_reclamo_o_inicio_trunc_90",
  "mean_tiempo_desde_ultimo_levante_pred", "n_contenedores_activos", "pct_contenedores_inferidos")
comparison <- do.call(rbind, lapply(fields, function(field) {
  data.frame(variable = field, different = sum(abs(prepared[[field]] - ref[[field]]) >
    1e-10, na.rm = TRUE), max_error = max(abs(prepared[[field]] - ref[[field]]), na.rm = TRUE))
}))
model <- readRDS(file.path(root, "runtime/r03_com/modelo_com.rds"))
pred <- rf_score_com(history, model, day, nrow(published))
pred <- pred[match(ref$cluster_id, pred$cluster_id), ]
report <- list(day = as.character(day), rows = nrow(ref), max_abs_error = max(abs(pred$pred_prob -
  ref$pred_prob)), feature_differences = comparison, interpretation = "Diferencias observadas entre resumen publicado y features actuales; causa de origen no inferida")
jsonlite::write_json(report, file.path(root, "config/diagnostico_mayo_r04.json"), pretty = TRUE,
  auto_unbox = TRUE)
print(comparison)
cat("MAYO_ERROR_MAX:", report$max_abs_error, "\n")
