library(arrow)
library(data.table)

##############################
## funciones
fun <- dir("funciones/", pattern = ".R", ignore.case = TRUE)
for (ii in fun) source(paste0("funciones/", ii))

################################
### Parametros
path_com <- "data/parquet/com"
path_levante <- "data/parquet/levante"
path_cluster_actual <- "data/processed/cluster_update_check/contenedor_posicion_cluster_actual"
out_base <- "data/processed/com_contenedor_cluster"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
umbral_asignacion_m <- 50
umbral_revision_m <- 100
redondeo_m <- 1
crs <- 32721

excluir_actividad_inferida_lejana <- FALSE
max_dias_total_tramo_inferido_estado <- NULL
usar_solo_contenedor_dia_elegible_modelo <- TRUE

################################
### Cargo datos preparados
datos_com <- as.data.table(arrow::open_dataset(path_com, format = "parquet"))
datos_levante <- as.data.table(arrow::open_dataset(path_levante, format = "parquet"))

contenedor_posicion_cluster <- as.data.table(
  arrow::open_dataset(path_cluster_actual, format = "parquet")
)

if (!is.na(target_version_cluster) && target_version_cluster != "") {
  contenedor_posicion_cluster <- contenedor_posicion_cluster[
    version_cluster == target_version_cluster
  ]
} else {
  versiones <- sort(unique(contenedor_posicion_cluster$version_cluster))
  target_version_cluster <- versiones[length(versiones)]
  contenedor_posicion_cluster <- contenedor_posicion_cluster[
    version_cluster == target_version_cluster
  ]
}

if (nrow(contenedor_posicion_cluster) == 0L) {
  stop("No hay mapeo contenedor-cluster para version_cluster = ", target_version_cluster)
}

################################
### Asigno reclamos COM a contenedores activos por dia
res <- asignar_com_a_contenedores_activos(
  datos_com = datos_com,
  datos_levante = datos_levante,
  contenedor_posicion_cluster = contenedor_posicion_cluster,
  redondeo_m = redondeo_m,
  umbral_asignacion_m = umbral_asignacion_m,
  umbral_revision_m = umbral_revision_m,
  excluir_actividad_inferida_lejana = excluir_actividad_inferida_lejana,
  max_dias_total_tramo_inferido_estado = max_dias_total_tramo_inferido_estado,
  usar_solo_contenedor_dia_elegible_modelo = usar_solo_contenedor_dia_elegible_modelo,
  crs = crs
)

################################
### Guardo resultados
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)

asignaciones_com <- res$asignaciones_com
asignaciones_com[, version_cluster := target_version_cluster]
asignaciones_com[, anio := as.integer(format(dia, "%Y"))]
asignaciones_com[, anio_mes := as.integer(format(dia, "%Y%m"))]

arrow::write_dataset(
  asignaciones_com,
  path = file.path(out_base, "asignaciones_com"),
  format = "parquet",
  partitioning = c("version_cluster", "anio", "anio_mes"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

resumen_asignacion <- data.table::copy(res$resumen_asignacion)
resumen_asignacion[, version_cluster := target_version_cluster]

arrow::write_dataset(
  resumen_asignacion,
  path = file.path(out_base, "resumen_asignacion"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

resumen_por_dia <- data.table::copy(res$resumen_por_dia)
resumen_por_dia[, version_cluster := target_version_cluster]
resumen_por_dia[, anio := as.integer(format(dia, "%Y"))]
resumen_por_dia[, anio_mes := as.integer(format(dia, "%Y%m"))]

arrow::write_dataset(
  resumen_por_dia,
  path = file.path(out_base, "resumen_por_dia"),
  format = "parquet",
  partitioning = c("version_cluster", "anio", "anio_mes"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

################################
### Salida de control
print(data.table::data.table(
  version_cluster = target_version_cluster,
  umbral_asignacion_m = umbral_asignacion_m,
  umbral_revision_m = umbral_revision_m,
  excluir_actividad_inferida_lejana = excluir_actividad_inferida_lejana,
  usar_solo_contenedor_dia_elegible_modelo = usar_solo_contenedor_dia_elegible_modelo,
  max_dias_total_tramo_inferido_estado = ifelse(
    is.null(max_dias_total_tramo_inferido_estado),
    NA_real_,
    max_dias_total_tramo_inferido_estado
  )
))

print(resumen_asignacion)
print(resumen_por_dia)

