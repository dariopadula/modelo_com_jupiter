source("../R/datos_fuente.R")

anterior <- Sys.getenv("APP_DATA_SOURCE", unset = NA_character_)
on.exit({
  if (is.na(anterior)) {
    Sys.unsetenv("APP_DATA_SOURCE")
  } else {
    Sys.setenv(APP_DATA_SOURCE = anterior)
  }
}, add = TRUE)

Sys.setenv(APP_DATA_SOURCE = "local")
stopifnot(!usar_s3_app(), fuente_datos_app() == "local")

Sys.setenv(APP_DATA_SOURCE = "s3")
stopifnot(usar_s3_app(), fuente_datos_app() == "cloudera_s3")

partes <- partes_key_detalle_app(paste0(
  "dario/modelo_com_app/data/historico/detalle_cluster_dia/",
  "dia_objetivo=2026-05-22/modelo_id=com_reclamo/part-0.parquet"
))
stopifnot(
  partes$dia == "2026-05-22",
  partes$modelo == "com_reclamo"
)

Sys.setenv(APP_DATA_SOURCE = "invalida")
error <- tryCatch({
  fuente_datos_app()
  FALSE
}, error = function(e) TRUE)
stopifnot(error)

cat("FUENTE_DATOS_OK\n")
