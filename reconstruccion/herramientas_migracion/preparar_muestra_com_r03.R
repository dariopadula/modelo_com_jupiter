# Puente de migracion explicito. Solo este inspector lee la version original.
all <- commandArgs(FALSE)
script <- sub("^--file=", "", grep("^--file=", all, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
args <- commandArgs(TRUE)
if (length(args) < 1L || length(args) > 2L) stop("Indicar raiz del repositorio original y opcionalmente dia")
old <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
.libPaths(c("C:/Users/dario/AppData/Local/R/win-library/4.5", .libPaths()))
for (pkg in c("arrow", "dplyr", "data.table", "jsonlite", "openssl", "sf")) if (!requireNamespace(pkg,
  quietly = TRUE)) stop("Falta paquete: ", pkg)

# Calcula SHA-256 por conexion de lectura sin cargar el archivo completo.  Entrada:
# ruta del archivo. Salida: hash como texto simple.
sha256 <- function(path) {
  con <- file(path, "rb")
  on.exit(close(con))
  unname(unclass(as.character(openssl::sha256(con))))
}
source(file.path(root, "R/features/com_receta.R"))
source(file.path(root, "R/modelos/com_logistico.R"))
source(file.path(root, "R/registro/contratos.R"))
out <- file.path(root, "runtime/r03_com")
if (dir.exists(out)) stop("La muestra R03 ya existe; no sobrescribir referencia")
manifest <- jsonlite::read_json(file.path(root, "config/referencia_local_r01.json"), simplifyVector = TRUE)
model_path <- "data/processed/modelos/logistico_cluster_dia_reducido_reclamos_d2/modelo_logistico_reducido.rds"
expected <- manifest$files$sha256[manifest$files$path == model_path]
if (length(expected) != 1L || sha256(file.path(old, model_path)) != expected) stop("Hash COM distinto de R01")
day <- as.Date(if (length(args) == 2L) args[[2L]] else "2026-03-31")
published <- arrow::open_dataset(file.path(old, "app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia"))
published <- dplyr::collect(dplyr::filter(published, modelo_id == "com_reclamo", dia_objetivo ==
  !!day))
published <- as.data.frame(published)
published <- published[order(published$ranking_dia), ]
ref <- head(published, 50L)
if (nrow(ref) != 50L || !identical(as.integer(ref$ranking_dia), 1:50)) stop("Muestra no contiene prefijo completo")
ids <- ref$cluster_id
start <- day - 180L
features <- arrow::open_dataset(file.path(old, "data/processed/modelo_cluster_dia/features_cluster_dia"))
columns <- unique(c("cluster_id", "dia", "version_cluster", "cluster_existente_dia", "n_reclamos",
  "tuvo_reclamo", "dias_historia_observada_cluster", "dias_desde_ultimo_reclamo_o_inicio",
  "sin_reclamo_previo_observado", "n_reclamos_lag1", "n_reclamos_sum_7d", "n_reclamos_sum_30d",
  "dias_cluster_existente_30d", "n_contenedores_activos", "pct_contenedores_inferidos",
  "mean_tiempo_desde_ultimo_levante_pred", "mean_levante_periodo", "mean_dias_total_tramo_inferido_estado"))
features <- dplyr::collect(dplyr::select(dplyr::filter(features, cluster_id %in% !!ids, dia >=
  !!start, dia <= !!day, version_cluster == "v2026_05_25", cluster_existente_dia == TRUE),
  dplyr::all_of(columns)))
model <- readRDS(file.path(old, model_path))
# La inferencia original usa coeficientes y prep; excluir fit/datos de ajuste.
model <- model[c("features_modelo", "prep", "coeficientes_prediccion", "rezago_reclamos_dias",
  "version_cluster")]
pred <- rf_score_com(features, model, day, nrow(published))
rf_prediction_contract(pred)
ref <- ref[match(pred$cluster_id, ref$cluster_id), ]
error <- max(abs(pred$pred_prob - ref$pred_prob))
same_rank <- identical(as.integer(pred$ranking_dia), as.integer(ref$ranking_dia))
if (error > 1e-10 || !same_rank) {
  debug <- file.path(root, "runtime", paste0("r03_diagnostico_", day))
  dir.create(debug, recursive = TRUE, showWarnings = FALSE)
  saveRDS(list(history = features, model = model, reference = ref, prediction = pred),
    file.path(debug, "comparacion.rds"))
  stop("Equivalencia COM no satisfecha: error=", format(error, digits = 16), " ranking=",
    same_rank)
}
maestro <- arrow::open_dataset(file.path(old, "app_operativa_v2/data/referencia/maestro_clusters"))
maestro <- as.data.frame(dplyr::collect(dplyr::filter(maestro, cluster_id %in% !!ids, version_cluster ==
  "v2026_05_25")))
if (anyDuplicated(maestro$cluster_id) || nrow(maestro) != 50L) stop("Maestro no corresponde a la muestra")
points <- sf::st_transform(sf::st_as_sf(maestro, coords = c("x", "y"), crs = 32721, remove = FALSE),
  4326)
coords <- sf::st_coordinates(points)
maestro$lng <- coords[, 1]
maestro$lat <- coords[, 2]
observed <- c("tuvo_reclamo_observado", "n_reclamos_observado", "estado_observacion", "estado_periodo_app",
  "fecha_reclamos_usada_hasta", "timestamp_corte_features")
for (key in observed) pred[[key]] <- ref[[key]]
# Metadatos retrospectivos se preservan como tales, no se certifica un corte diario.
pred$metadata_source <- "publicacion_retrospectiva_r01"
product <- merge(pred, maestro[c("cluster_id", "barrio", "lng", "lat")], by = "cluster_id",
  all.x = TRUE, sort = FALSE)
product <- product[order(product$ranking_dia), ]
if (anyNA(product[c("lng", "lat")])) stop("Mapa incompleto")
dir.create(out, recursive = TRUE)
saveRDS(model, file.path(out, "modelo_com.rds"))
saveRDS(list(history = features, day = day, universe_n = nrow(published)), file.path(out,
  "entrada.rds"))
saveRDS(ref, file.path(out, "referencia_predicciones.rds"))
saveRDS(maestro, file.path(out, "maestro.rds"))
saveRDS(product, file.path(out, "producto_com.rds"))
report <- list(sample_id = paste0("r03_com_", day, "_top50"), model_sha256 = expected, day = as.character(day),
  context_from = as.character(start), rows_history = nrow(features), rows_sample = nrow(pred),
  universe_reference = nrow(published), max_abs_error = error, tolerance = 1e-10, same_ranking = same_rank,
  observational_state = "copied_from_reference_not_recomputed", scope = "top50_retrospective_sample_not_daily_production",
  product_sha256 = sha256(file.path(out, "producto_com.rds")), inference_bundle_sha256 = sha256(file.path(out,
    "modelo_com.rds")))
jsonlite::write_json(report, file.path(root, "config/equivalencia_com_r03.json"), pretty = TRUE,
  auto_unbox = TRUE)
cat("R03_MUESTRA_OK\n")
print(report[c("rows_history", "rows_sample", "universe_reference", "max_abs_error", "same_ranking")])
