library(arrow)
library(data.table)

source("funciones/scoring_operativo_utils.R")

################################
### Parametros
path_features <- Sys.getenv(
  "PATH_FEATURES",
  unset = "data/processed/modelo_cluster_dia/features_cluster_dia"
)
out_base <- Sys.getenv("OUT_BASE_APP", unset = "data/processed/app_emulacion")

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
fecha_estado <- data.table::as.IDate(Sys.getenv("FECHA_ESTADO", unset = NA_character_))
fecha_reclamos_cerrada_hasta <- data.table::as.IDate(Sys.getenv("FECHA_RECLAMOS_CERRADA_HASTA", unset = NA_character_))
target_col <- "tuvo_reclamo"

if (is.na(fecha_estado)) {
  stop("Debe definir FECHA_ESTADO")
}
if (is.na(fecha_reclamos_cerrada_hasta)) {
  fecha_reclamos_cerrada_hasta <- fecha_estado
}

out_estado <- file.path(out_base, "estado_historico_cluster")

################################
### Cargo datos
datos <- as.data.table(arrow::open_dataset(path_features, format = "parquet"))

if (!is.na(target_version_cluster) && target_version_cluster != "") {
  datos <- datos[version_cluster == target_version_cluster]
} else {
  versiones <- sort(unique(datos$version_cluster))
  target_version_cluster <- versiones[length(versiones)]
  datos <- datos[version_cluster == target_version_cluster]
}

if (nrow(datos) == 0L) {
  stop("No hay datos para version_cluster = ", target_version_cluster)
}

################################
### Construyo estado historico
estado <- construir_estado_historico_cluster(
  datos_cluster_dia = datos,
  fecha_estado = fecha_estado,
  fecha_reclamos_cerrada_hasta = fecha_reclamos_cerrada_hasta,
  target_col = target_col
)
estado[, version_cluster := target_version_cluster]

resumen <- data.table(
  fecha_estado = fecha_estado,
  fecha_reclamos_cerrada_hasta = fecha_reclamos_cerrada_hasta,
  version_cluster = target_version_cluster,
  clusters = nrow(estado),
  clusters_activos_fecha_estado = sum(estado$cluster_activo_fecha_estado == TRUE, na.rm = TRUE),
  clusters_sin_reclamo_previo = sum(estado$sin_reclamo_previo_observado == TRUE, na.rm = TRUE),
  clusters_historia_0_6 = sum(estado$dias_historia_observada_cluster >= 0 & estado$dias_historia_observada_cluster <= 6, na.rm = TRUE),
  clusters_historia_7_29 = sum(estado$historia_observada_7_29 == TRUE, na.rm = TRUE),
  clusters_historia_30_89 = sum(estado$historia_observada_30_89 == TRUE, na.rm = TRUE),
  clusters_historia_90_179 = sum(estado$historia_observada_90_179 == TRUE, na.rm = TRUE),
  clusters_historia_180_mas = sum(estado$historia_observada_180_mas == TRUE, na.rm = TRUE),
  reclamos_acumulados = sum(estado$n_reclamos_acumulados, na.rm = TRUE)
)

################################
### Guardo resultados
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)

escribir_dataset_reemplazo(
  estado,
  out_estado,
  partitioning = c("version_cluster", "fecha_estado")
)

escribir_dataset_reemplazo(
  resumen,
  file.path(out_base, "resumen_estado_historico_cluster"),
  partitioning = c("version_cluster", "fecha_estado")
)

################################
### Salida de control
print(resumen)
print(estado[1:20])
