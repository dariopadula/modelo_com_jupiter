library(data.table)
library(arrow)
library(lubridate)

modo_datos <- Sys.getenv("MODO_DATOS_LEVANTE", unset = "local")

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
out_save <- "data/parquet/levante"

if (!dir.exists(out_save)) dir.create(out_save, recursive = TRUE)

###############################
### Meses objetivo: son los meses que se van a guardar al final.
anio_mes_objetivo <- c(202501:202512, 202601:202605)

###############################
### Actualizacion
actualizar <- FALSE
meses_contexto_previos <- 1

### Meses de lectura: incluyen contexto previo para calcular bien
### el tiempo desde el ultimo levante de cada mes objetivo.
anio_mes_lectura <- meses_lectura_con_contexto(
  anio_mes_objetivo,
  meses_contexto_previos = meses_contexto_previos
)

###############################
datos <- cargar_datos_levante(
  modo = modo_datos,
  anio_mes = anio_mes_lectura,
  actualizar = actualizar
)

datos <- preparar_datos_levante(
  datos,
  anio_mes_objetivo = anio_mes_objetivo
)

##########################################
##### Chequeo basico
cont01 <- datos[
  !is.na(fecha_levante),
  .(
    fecha_min = min(dia),
    fecha_max = max(dia),
    N = .N
  ),
  by = levante_contenedor_id
][
  order(-N)
]

print(dim(datos))
print(head(cont01))

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
