library(arrow)
library(data.table)
library(dplyr)

path_predicciones <- Sys.getenv(
  "PATH_PREDICCIONES_APP",
  unset = "app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia"
)
path_cluster <- Sys.getenv(
  "PATH_CLUSTER_ACTUAL",
  unset = "data/processed/cluster_update_check/contenedor_posicion_cluster_actual"
)
path_admin <- Sys.getenv(
  "PATH_CLUSTER_ADMIN",
  unset = "data/processed/cluster_territorial/cluster_admin_territorial"
)
out_path <- Sys.getenv(
  "OUT_MAESTRO_APP",
  unset = "app_operativa_v2/data/referencia/maestro_clusters"
)
sobrescribir <- identical(Sys.getenv("SOBRESCRIBIR", unset = "0"), "1")

for (path in c(path_predicciones, path_cluster, path_admin)) {
  if (!dir.exists(path)) stop("No existe la fuente requerida: ", path)
}
if (dir.exists(out_path) && !sobrescribir) {
  stop("La salida ya existe: ", out_path, ". Use SOBRESCRIBIR=1 para reconstruirla.")
}

ds_pred <- open_dataset(path_predicciones, format = "parquet")
versiones <- ds_pred |>
  distinct(version_cluster) |>
  collect() |>
  as.data.table()
if (nrow(versiones) != 1L || is.na(versiones$version_cluster[[1]])) {
  stop("Las predicciones deben contener una unica version_cluster")
}
version_objetivo <- versiones$version_cluster[[1]]

clusters_predichos <- ds_pred |>
  distinct(cluster_id) |>
  collect() |>
  as.data.table()
fechas_predicciones <- ds_pred |>
  summarise(
    desde = min(dia_objetivo, na.rm = TRUE),
    hasta = max(dia_objetivo, na.rm = TRUE)
  ) |>
  collect() |>
  as.data.table()

mapa <- open_dataset(path_cluster, format = "parquet") |>
  filter(version_cluster == !!version_objetivo) |>
  collect() |>
  as.data.table()
admin <- open_dataset(path_admin, format = "parquet") |>
  filter(version_cluster == !!version_objetivo) |>
  collect() |>
  as.data.table()

maestro <- mapa[!is.na(cluster_id), .(
  x = mean(x, na.rm = TRUE),
  y = mean(y, na.rm = TRUE),
  n_posiciones_cluster = .N,
  circuitos = paste(
    head(sort(unique(na.omit(levante_circuito))), 3L),
    collapse = ", "
  )
), by = .(version_cluster, cluster_id)]

admin <- unique(admin[, .(
  version_cluster,
  cluster_id,
  barrio = nombre_barrio_ine,
  cod_barrio_ine = as.character(cod_barrio_ine)
)])
maestro <- admin[maestro, on = c("version_cluster", "cluster_id")]

if (anyDuplicated(maestro$cluster_id)) stop("El maestro contiene clusters duplicados")
if (any(!is.finite(maestro$x) | !is.finite(maestro$y))) {
  stop("El maestro contiene coordenadas no validas")
}
faltantes <- setdiff(clusters_predichos$cluster_id, maestro$cluster_id)
if (length(faltantes)) {
  stop("Faltan ", length(faltantes), " clusters predichos en el maestro")
}

staging <- paste0(out_path, ".staging")
backup <- paste0(out_path, ".backup")
if (dir.exists(staging)) unlink(staging, recursive = TRUE)
if (dir.exists(backup)) unlink(backup, recursive = TRUE)
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
write_dataset(
  maestro,
  path = staging,
  format = "parquet",
  compression = "zstd",
  existing_data_behavior = "overwrite"
)

publicado <- open_dataset(staging, format = "parquet") |>
  summarise(filas = n(), clusters = n_distinct(cluster_id)) |>
  collect()
if (publicado$filas[[1]] != nrow(maestro) || publicado$clusters[[1]] != nrow(maestro)) {
  stop("La validacion del maestro publicado no coincide")
}

if (dir.exists(out_path) && !file.rename(out_path, backup)) {
  stop("No se pudo respaldar el maestro anterior")
}
if (!file.rename(staging, out_path)) {
  if (dir.exists(backup)) file.rename(backup, out_path)
  stop("No se pudo publicar el maestro nuevo")
}
if (dir.exists(backup)) unlink(backup, recursive = TRUE)

print(data.table(
  version_cluster = version_objetivo,
  clusters = nrow(maestro),
  desde_predicciones = fechas_predicciones$desde,
  hasta_predicciones = fechas_predicciones$hasta
))
cat("MAESTRO_APP_OK\n")
