# Validacion remota explicita. Solo ejecutar con prefijos aislados confirmados.
# No es parte de test_acceso_r09.R; requiere CML real y una entrega pequena con cierre.
arguments <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
source(file.path(root, "R/configuracion/runtime_r07.R"))
rf_init_r07()
source(file.path(root, "R/acceso/cargar_acceso.R"))
rf_load_access(root)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("Uso: validar_s3_real_r09.R <entrega_local> <publicacion_piloto> <id_nuevo>")
config <- rf_config(root)
if (any(config$values[c("INGESTA_INPUT_BACKEND", "PIPELINE_STORAGE_BACKEND", "APP_DATA_SOURCE")] != "cloudera_s3")) {
  stop("Esta validacion exige los tres backends S3 reales")
}
if (config$values[["PIPELINE_S3_BUCKET"]] != config$values[["APP_S3_BUCKET"]] ||
    config$values[["PIPELINE_S3_PREFIX"]] != config$values[["APP_S3_PREFIX"]]) stop("Pipeline/app deben apuntar al mismo almacen aislado")
input <- rf_store(config, "input", "")
store <- rf_store(config, "pipeline", "")
next_id <- rf_version_id(paste0(args[[3L]], "_next"))
if (length(rf_store_list(store, "versions/")) || "current.json" %in% rf_store_list(store, "current.json")) {
  stop("La validacion remota requiere un almacen aislado nuevo, sin publicaciones")
}
cache <- file.path(config$values[["RF_RUNTIME_PATH"]], paste0("remoto_", rf_version_id(args[[3L]])))
manifest_key <- substring(config$values[["INGESTA_S3_MANIFEST_KEY"]], nchar(input$prefix) + 2L)
rf_publish_delivery(args[[1L]], input, manifest_key, cache)
delivery <- rf_materialize_delivery(input, manifest_key, cache)
rf_publish_version(args[[2L]], store, args[[3L]])
rf_activate_version(store, args[[3L]], cache)
context <- rf_app_context(config)
stopifnot(context$view$id == args[[3L]])
for (family in c("com_reclamo", "zl_problema")) {
  dates <- as.character(unlist(context$view$inventory$history_days[[family]]))
  if (length(dates)) rf_app_fetch_day(context, dates[[1L]], family)
}
rf_publish_version(args[[2L]], store, next_id)
rf_activate_version(store, next_id, cache)
stopifnot(context$view$id == args[[3L]], rf_store_json(store, "current.json")$publication_id == next_id)
rf_restore_publication(store, cache)
stopifnot(rf_store_json(store, "current.json")$publication_id == args[[3L]])
cat("R09_S3_REAL_OK: delivery=", delivery$delivery_id, " publication=", context$view$id, "\n", sep = "")
