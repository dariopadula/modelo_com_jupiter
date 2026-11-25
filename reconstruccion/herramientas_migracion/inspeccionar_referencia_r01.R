# Inspeccion acotada de referencia local; no entrena ni modifica fuentes.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Indicar raiz absoluta del repositorio")
root <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
.libPaths(c("C:/Users/dario/AppData/Local/R/win-library/4.5", .libPaths()))
for (pkg in c("arrow", "dplyr", "jsonlite")) {
  if (!requireNamespace(pkg, quietly = TRUE))
    stop("Falta paquete instalado: ", pkg)
}
out <- file.path(root, "reconstruccion/runtime/referencia_r01")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

# Resuelve una ruta de evidencia dentro del repositorio inspeccionado.  Entrada: ruta
# relativa. Salida: ruta completa; solo herramienta de migracion.
p <- function(x) file.path(root, x)
com <- readRDS(p("data/processed/modelos/logistico_cluster_dia_reducido_reclamos_d2/modelo_logistico_reducido.rds"))
zl <- readRDS(p("data/processed/modelos/experimentos_cascada_zl/operativo_segmento/modelo_zl_xgboost.rds"))
a0 <- readRDS(p("outputs/prueba_xgboost_correccion_estructural_com/modelo_A0_final.rds"))
p3 <- readRDS(p("outputs/comparacion_poda_xgboost_com/modelo_P3_compacto.rds"))

# Extrae solo los metadatos permitidos del artefacto inspeccionado.  Entradas: objeto y
# nombres. Salida: subconjunto sin fit ni datos de entrenamiento.
campos <- function(x, fields) x[intersect(fields, names(x))]
meta <- list(R = R.version.string, paquetes = setNames(lapply(c("arrow", "dplyr", "jsonlite",
  "xgboost", "mgcv"), function(x) {
  if (requireNamespace(x, quietly = TRUE)) as.character(utils::packageVersion(x)) else NA_character_
}), c("arrow", "dplyr", "jsonlite", "xgboost", "mgcv")), com = campos(com, c("features_modelo",
  "meses_train", "meses_validacion", "meses_test", "fecha_min_modelo", "rezago_reclamos_dias",
  "version_cluster", "usar_exceso_levante", "no_agregar_na_features")), com_prep_campos = names(com$prep),
  zl = campos(zl, c("features_numericas", "features_categoricas", "feature_set_zl", "version_cluster")),
  zl_campos = names(zl), escenario_zl_presente = "random_dia_estratificado_mes" %in% names(zl),
  zl_escenario_campos = names(zl[["random_dia_estratificado_mes"]]), a0_clase = class(a0),
  a0_formula = paste(deparse(stats::formula(a0)), collapse = " "), p3_clase = class(p3),
  p3_features = tryCatch(p3$feature_names, error = function(e) NULL))
day <- as.Date("2026-05-24")
predpath <- p("app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia")
samples <- lapply(c("com_reclamo", "zl_problema"), function(id) {
  ds <- arrow::open_dataset(predpath, format = "parquet")
  q <- dplyr::filter(ds, modelo_id == !!id, dia_objetivo == !!day)
  dplyr::collect(utils::head(q, 8L))
})
pred <- dplyr::bind_rows(samples)
utils::write.csv(pred, file.path(out, "muestra_predicciones.csv"), row.names = FALSE, na = "")
ids <- unique(pred$cluster_id)
maestro <- arrow::open_dataset(p("app_operativa_v2/data/referencia/maestro_clusters"))
maestro <- dplyr::collect(dplyr::filter(maestro, cluster_id %in% !!ids))
utils::write.csv(maestro, file.path(out, "muestra_maestro.csv"), row.names = FALSE, na = "")
serie <- arrow::open_dataset(p("app_operativa_v2/data/historico/serie_historica_com"))
serie <- dplyr::collect(utils::head(dplyr::filter(serie, dia_objetivo == !!day), 8L))
utils::write.csv(serie, file.path(out, "muestra_serie.csv"), row.names = FALSE, na = "")
meta$muestra <- list(dia = as.character(day), filas_pred = nrow(pred), modelos = unique(pred$modelo_id),
  versiones_cluster = unique(pred$version_cluster), filas_maestro = nrow(maestro), filas_serie = nrow(serie),
  escenarios = unique(serie$escenario))
stopifnot(nrow(pred) == 16L, length(unique(pred$modelo_id)) == 2L, identical(as.character(unique(pred$version_cluster)),
  as.character(com$version_cluster)), isTRUE(meta$escenario_zl_presente), nrow(maestro) >
  0L, nrow(serie) > 0L)
jsonlite::write_json(meta, file.path(out, "metadatos_modelos.json"), pretty = TRUE, auto_unbox = TRUE,
  null = "null")
cat("R01_INSPECCION_OK\n")
cat(jsonlite::toJSON(meta$muestra, auto_unbox = TRUE, pretty = TRUE), "\n")
