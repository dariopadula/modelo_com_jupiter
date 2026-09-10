library(arrow)
library(dbscan)
library(data.table)

##############################
## funciones
fun <- dir("funciones/", pattern = ".R", ignore.case = TRUE)
for (ii in fun) source(paste0("funciones/", ii))

################################
### Parametros
path_levante <- "data/parquet/levante"
out_base <- "data/reference/clusters"

eps_m <- 50
min_pts <- 2
crs <- 32721
redondeo_m <- 1
version_cluster <- paste0("v", format(Sys.Date(), "%Y_%m_%d"))

################################
### Cargo datos preparados de levantes
datos_levante <- as.data.table(arrow::open_dataset(path_levante, format = "parquet"))
datos_levante <- datos_levante[!is.na(anio)]

################################
### Entreno referencia
clusters <- entrenar_clusters_referencia(
  datos_levante = datos_levante,
  eps_m = eps_m,
  min_pts = min_pts,
  version_cluster = version_cluster,
  crs = crs,
  redondeo_m = redondeo_m
)

################################
### Guardo objetos
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)

arrow::write_dataset(
  clusters$cluster_members_ref,
  path = file.path(out_base, "cluster_members_ref"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

arrow::write_dataset(
  clusters$cluster_summary_ref,
  path = file.path(out_base, "cluster_summary_ref"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

arrow::write_dataset(
  clusters$cluster_metadata,
  path = file.path(out_base, "cluster_metadata"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

arrow::write_dataset(
  clusters$contenedor_posicion_cluster,
  path = file.path(out_base, "contenedor_posicion_cluster"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

################################
### Chequeos basicos
print(clusters$cluster_metadata)
print(clusters$cluster_summary_ref[, .N, by = tipo_cluster])
print(summary(clusters$cluster_summary_ref$n_puntos))


