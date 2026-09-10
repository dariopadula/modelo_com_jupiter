library(data.table)
library(arrow)
library(sf)

modo_datos <- Sys.getenv("MODO_DATOS_COM", unset = "local")

if (modo_datos == "servidor") {
  library(RJDBC)
  library(DBI)
  library(rJava)
}

fun <- dir("funciones/", pattern = ".R", ignore.case = TRUE)
for (ii in fun) source(file.path("funciones", ii))
source("zona_limpia/funciones_zona_limpia.R")

out_com_completo <- "data/parquet/com_completo"

if (!dir.exists(out_com_completo)) dir.create(out_com_completo, recursive = TRUE)

anio_mes <- c(202501:202512, 202601:202605)
actualizar <- FALSE

datos_raw <- cargar_datos_com(
  modo = modo_datos,
  anio_mes = anio_mes,
  actualizar = actualizar
)

datos_modelo <- preparar_datos_com(data.table::copy(datos_raw))
datos_completo <- preparar_datos_com_completo(data.table::copy(datos_raw))

print(data.table(
  salida = c("com_modelo", "com_completo"),
  filas = c(nrow(datos_modelo), nrow(datos_completo))
))

print(datos_completo[, .N, by = .(es_incidente_modelo, es_zona_limpia)][order(es_incidente_modelo, es_zona_limpia)])

write_dataset(
  datos_completo,
  path = out_com_completo,
  format = "parquet",
  partitioning = c("anio", "anio_mes"),
  existing_data_behavior = "overwrite",
  compression = "zstd"
)
