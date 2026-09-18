library(arrow)
library(data.table)

##############################
## funciones
fun <- dir("funciones/", pattern = ".R", ignore.case = TRUE)
for (ii in fun) source(paste0("funciones/", ii))

################################
### Parametros
path_levante <- "data/parquet/levante"
path_clusters <- "data/reference/clusters"
out_base <- "data/processed/cluster_update_check"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
umbral_asignacion_m <- 50
umbral_revision_m <- 100
crs <- 32721

################################
### Cargo referencia de clusters
cluster_metadata <- as.data.table(
  arrow::open_dataset(file.path(path_clusters, "cluster_metadata"))
)

if (is.na(target_version_cluster) || target_version_cluster == "") {
  setorder(cluster_metadata, fecha_entrenamiento, version_cluster)
  target_version_cluster <- cluster_metadata[.N, version_cluster]
}

cluster_members_ref <- as.data.table(
  arrow::open_dataset(file.path(path_clusters, "cluster_members_ref"))
)[version_cluster == target_version_cluster]

metadata_ref <- cluster_metadata[version_cluster == target_version_cluster]
if (nrow(metadata_ref) != 1) {
  stop("No se encontro una unica metadata para version_cluster = ", target_version_cluster)
}

################################
### Cargo levantes procesados actuales
datos_levante <- as.data.table(arrow::open_dataset(path_levante, format = "parquet"))
datos_levante <- datos_levante[!is.na(anio)]

################################
### Asigno posiciones actuales contra referencia fija
res <- asignar_posiciones_levante_a_clusters(
  datos_levante = datos_levante,
  cluster_members_ref = cluster_members_ref,
  redondeo_m = metadata_ref$redondeo_m,
  umbral_asignacion_m = umbral_asignacion_m,
  umbral_revision_m = umbral_revision_m,
  crs = crs
)

################################
### Guardo diagnostico. No modifica la referencia.
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)

arrow::write_dataset(
  res$posiciones_nuevas_asignadas,
  path = file.path(out_base, "posiciones_nuevas_asignadas"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

arrow::write_dataset(
  res$posiciones_cluster_actual,
  path = file.path(out_base, "posiciones_cluster_actual"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

arrow::write_dataset(
  res$contenedor_posicion_cluster_actual,
  path = file.path(out_base, "contenedor_posicion_cluster_actual"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

arrow::write_dataset(
  res$resumen_asignacion,
  path = file.path(out_base, "resumen_asignacion"),
  format = "parquet",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

################################
### Salida de control
print(metadata_ref)
print(res$resumen_asignacion)

if (nrow(res$posiciones_nuevas_asignadas) > 0) {
  print(res$posiciones_nuevas_asignadas[, .N, by = estado_asignacion])
  print(summary(res$posiciones_nuevas_asignadas$distancia_m))
} else {
  message("No se detectaron posiciones nuevas frente a la referencia.")
}

