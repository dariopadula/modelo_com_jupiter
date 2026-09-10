library(arrow)
library(data.table)

##############################
## funciones
fun <- dir("funciones/", pattern = ".R", ignore.case = TRUE)
for (ii in fun) source(paste0("funciones/", ii))

################################
### Parametros
path_levante <- "data/parquet/levante"
path_asignaciones_com <- "data/processed/com_contenedor_cluster/asignaciones_com"
path_cluster_actual <- "data/processed/cluster_update_check/contenedor_posicion_cluster_actual"
out_base <- "data/processed/modelo_cluster_dia"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
redondeo_m <- 1
estados_com_validos <- c("asignado", "revision")
limitar_rango_fechas_com <- TRUE
usar_solo_contenedor_dia_elegible_modelo <- TRUE

################################
### Cargo datos
datos_levante <- as.data.table(arrow::open_dataset(path_levante, format = "parquet"))
asignaciones_com <- as.data.table(arrow::open_dataset(path_asignaciones_com, format = "parquet"))
contenedor_posicion_cluster <- as.data.table(
  arrow::open_dataset(path_cluster_actual, format = "parquet")
)

if (!is.na(target_version_cluster) && target_version_cluster != "") {
  asignaciones_com <- asignaciones_com[version_cluster == target_version_cluster]
  contenedor_posicion_cluster <- contenedor_posicion_cluster[version_cluster == target_version_cluster]
} else {
  versiones <- sort(unique(contenedor_posicion_cluster$version_cluster))
  target_version_cluster <- versiones[length(versiones)]
  asignaciones_com <- asignaciones_com[version_cluster == target_version_cluster]
  contenedor_posicion_cluster <- contenedor_posicion_cluster[version_cluster == target_version_cluster]
}

if (nrow(asignaciones_com) == 0L) {
  stop("No hay asignaciones COM para version_cluster = ", target_version_cluster)
}
if (nrow(contenedor_posicion_cluster) == 0L) {
  stop("No hay mapeo contenedor-cluster para version_cluster = ", target_version_cluster)
}

################################
### Construyo base cluster/dia
res <- construir_base_cluster_dia(
  datos_levante = datos_levante,
  asignaciones_com = asignaciones_com,
  contenedor_posicion_cluster = contenedor_posicion_cluster,
  redondeo_m = redondeo_m,
  estados_com_validos = estados_com_validos,
  limitar_rango_fechas_com = limitar_rango_fechas_com,
  usar_solo_contenedor_dia_elegible_modelo = usar_solo_contenedor_dia_elegible_modelo
)

################################
### Guardo resultados
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
unlink(file.path(out_base, c("base_cluster_dia", "com_cluster_dia", "resumen")), recursive = TRUE)

base_cluster_dia <- data.table::copy(res$base_cluster_dia)
base_cluster_dia[, version_cluster := target_version_cluster]

arrow::write_dataset(
  base_cluster_dia,
  path = file.path(out_base, "base_cluster_dia"),
  format = "parquet",
  partitioning = c("version_cluster", "anio", "anio_mes"),
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

com_cluster_dia <- data.table::copy(res$com_cluster_dia)
com_cluster_dia[, version_cluster := target_version_cluster]

arrow::write_dataset(
  com_cluster_dia,
  path = file.path(out_base, "com_cluster_dia"),
  format = "parquet",
  partitioning = c("version_cluster", "anio", "anio_mes"),
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

resumen <- data.table::copy(res$resumen)
resumen[, version_cluster := target_version_cluster]

arrow::write_dataset(
  resumen,
  path = file.path(out_base, "resumen"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

################################
### Salida de control
print(data.table::data.table(
  version_cluster = target_version_cluster,
  estados_com_validos = paste(estados_com_validos, collapse = ","),
  limitar_rango_fechas_com = limitar_rango_fechas_com,
  usar_solo_contenedor_dia_elegible_modelo = usar_solo_contenedor_dia_elegible_modelo
))
print(resumen)
print(base_cluster_dia[, .N, by = tuvo_reclamo])
print(summary(base_cluster_dia$n_contenedores_activos))
