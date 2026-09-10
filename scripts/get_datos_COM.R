library(data.table)
library(arrow)
library(sf)

modo_datos <- Sys.getenv("MODO_DATOS_COM", unset = "local")

if (modo_datos == "servidor") {
  library(RJDBC)
  library(DBI)
  library(rJava)
}

##############################
## funciones
fun <- dir("funciones/", pattern = ".R", ignore.case = TRUE)
for (ii in fun) source(paste0("funciones/", ii))

##############################
##### directorios
out_save <- "data/parquet/com"

if (!dir.exists(out_save)) dir.create(out_save, recursive = TRUE)

###############################
### Meses con el periodo de interes
anio_mes <- c(202501:202512, 202601:202605)

###############################
### Actualizacion
actualizar <- FALSE

###############################
datos <- cargar_datos_com(
  modo = modo_datos,
  anio_mes = anio_mes,
  actualizar = actualizar
)

datos <- preparar_datos_com(datos)

##########################################
##### Chequeo basico
print(dim(datos))
print(datos[, .N, by = .(incidente, repetido)][order(incidente, repetido)])

##########################################
##### Guardo en parquet
existing_data_behavior <- if (actualizar) "delete_matching" else "overwrite"

write_dataset(
  datos,
  path = out_save,
  format = "parquet",
  partitioning = c("anio", "anio_mes"),
  existing_data_behavior = existing_data_behavior,
  compression = "zstd"
)


