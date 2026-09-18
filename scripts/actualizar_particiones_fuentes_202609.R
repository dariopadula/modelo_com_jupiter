library(arrow)
library(data.table)
library(dplyr)
library(sf)
library(lubridate)
library(zoo)

Sys.setenv(TZ = "America/Montevideo")

fun <- dir("funciones", pattern = "\\.R$", full.names = TRUE, ignore.case = TRUE)
for (archivo in fun) source(archivo)
source("zona_limpia/funciones_zona_limpia.R")

fecha_corte <- as.IDate("2026-09-14")
meses_com_reemplazar <- 202604:202609
meses_levante_reemplazar <- 202605:202609
meses_levante_contexto <- 202604

path_com_raw <- "data/paraprobar/datos_com.parquet"
path_levante_raw <- "data/paraprobar/datos_levante.parquet"
path_com <- "data/parquet/com"
path_com_completo <- "data/parquet/com_completo"
path_levante <- "data/parquet/levante"
out_dir <- "outputs/auditoria_actualizacion_202609"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

normalizar_fechas_com_snapshot <- function(dt) {
  setDT(dt)
  for (col in intersect(c("fecha_de_reclamo", "fecha_resuelto"), names(dt))) {
    if (inherits(dt[[col]], "POSIXt")) {
      # El parquet local contiene timestamps sin zona que representan la hora
      # civil original. Se conserva esa hora antes de asignar Montevideo.
      set(dt, j = col, value = format(dt[[col]], "%Y-%m-%d %H:%M:%OS6", tz = "UTC"))
    }
  }
  dt[]
}

leer_meses <- function(path, meses) {
  ds <- arrow::open_dataset(path, format = "parquet")
  as.data.table(dplyr::collect(dplyr::filter(ds, anio_mes %in% meses)))
}

resumen_mensual_dataset <- function(path, nombre) {
  if (!dir.exists(path)) return(data.table())
  ds <- arrow::open_dataset(path, format = "parquet")
  as.data.table(
    dplyr::collect(dplyr::count(ds, anio_mes, name = "filas"))
  )[, dataset := nombre][]
}

validar_objeto <- function(dt, meses, nombre) {
  if (nrow(dt) == 0L) stop(nombre, " quedo vacio")
  if (!setequal(sort(unique(dt$anio_mes)), meses)) {
    stop(nombre, " no contiene exactamente los meses esperados")
  }
  if (max(dt$dia, na.rm = TRUE) > fecha_corte) {
    stop(nombre, " contiene fechas posteriores al corte")
  }
  duplicadas <- dt[, .N, by = intersect(c("id", "cluster_id", "levante_contenedor_id", "dia"), names(dt))][N > 1L]
  if (nombre == "levante" && nrow(duplicadas) > 0L) {
    stop("levante contiene mas de una fila por contenedor/dia")
  }
  invisible(TRUE)
}

cat("Preparando COM y COM ampliado...\n")
com_raw <- leer_meses(path_com_raw, meses_com_reemplazar)
com_raw <- normalizar_fechas_com_snapshot(com_raw)

com_modelo <- preparar_datos_com(copy(com_raw))
com_modelo <- com_modelo[dia <= fecha_corte]
validar_objeto(com_modelo, meses_com_reemplazar, "com_modelo")

com_completo <- preparar_datos_com_completo(copy(com_raw))
com_completo <- com_completo[dia <= fecha_corte]
validar_objeto(com_completo, meses_com_reemplazar, "com_completo")
rm(com_raw)
gc()

cat("Preparando levantes con abril como contexto...\n")
levante_raw <- leer_meses(
  path_levante_raw,
  c(meses_levante_contexto, meses_levante_reemplazar)
)
levante <- preparar_datos_levante(
  levante_raw,
  anio_mes_objetivo = meses_levante_reemplazar,
  fecha_max = fecha_corte
)
validar_objeto(levante, meses_levante_reemplazar, "levante")
rm(levante_raw)
gc()

antes <- rbindlist(list(
  resumen_mensual_dataset(path_com, "com"),
  resumen_mensual_dataset(path_com_completo, "com_completo"),
  resumen_mensual_dataset(path_levante, "levante")
), fill = TRUE)

cat("Escribiendo solamente las particiones validadas...\n")
arrow::write_dataset(
  com_modelo,
  path = path_com,
  format = "parquet",
  partitioning = c("anio", "anio_mes"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)
arrow::write_dataset(
  com_completo,
  path = path_com_completo,
  format = "parquet",
  partitioning = c("anio", "anio_mes"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)
arrow::write_dataset(
  levante,
  path = path_levante,
  format = "parquet",
  partitioning = c("anio", "anio_mes"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

despues <- rbindlist(list(
  resumen_mensual_dataset(path_com, "com"),
  resumen_mensual_dataset(path_com_completo, "com_completo"),
  resumen_mensual_dataset(path_levante, "levante")
), fill = TRUE)

control <- merge(
  antes,
  despues,
  by = c("dataset", "anio_mes"),
  all = TRUE,
  suffixes = c("_antes", "_despues")
)
control[, cambio := filas_despues - filas_antes]

meses_no_objetivo_cambiados <- control[
  (dataset %in% c("com", "com_completo") & !anio_mes %in% meses_com_reemplazar) |
    (dataset == "levante" & !anio_mes %in% meses_levante_reemplazar)
][!is.na(cambio) & cambio != 0L]
if (nrow(meses_no_objetivo_cambiados) > 0L) {
  stop("Se modificaron particiones que no eran objetivo")
}

fwrite(control, file.path(out_dir, "control_particiones_antes_despues.csv"))

cat("\nControl de particiones actualizadas\n")
print(control[anio_mes >= 202604][order(dataset, anio_mes)])
cat("\nActualizacion terminada con corte en ", as.character(fecha_corte), ".\n", sep = "")
