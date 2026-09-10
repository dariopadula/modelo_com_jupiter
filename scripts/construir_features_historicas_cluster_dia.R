library(arrow)
library(data.table)
library(zoo)

##############################
## funciones
fun <- dir("funciones/", pattern = ".R", ignore.case = TRUE)
for (ii in fun) source(paste0("funciones/", ii))

################################
### Parametros
path_base_cluster_dia <- "data/processed/modelo_cluster_dia/base_cluster_dia"
out_base <- "data/processed/modelo_cluster_dia"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
ventanas_dias <- c(7L, 30L)

################################
### Cargo datos
base_cluster_dia <- as.data.table(
  arrow::open_dataset(path_base_cluster_dia, format = "parquet")
)

if (!is.na(target_version_cluster) && target_version_cluster != "") {
  base_cluster_dia <- base_cluster_dia[version_cluster == target_version_cluster]
} else {
  versiones <- sort(unique(base_cluster_dia$version_cluster))
  target_version_cluster <- versiones[length(versiones)]
  base_cluster_dia <- base_cluster_dia[version_cluster == target_version_cluster]
}

if (nrow(base_cluster_dia) == 0L) {
  stop("No hay base cluster-dia para version_cluster = ", target_version_cluster)
}

################################
### Construyo features historicas
res <- construir_features_historicas_cluster_dia(
  base_cluster_dia = base_cluster_dia,
  ventanas_dias = ventanas_dias
)

################################
### Guardo resultados
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
unlink(file.path(out_base, c("features_cluster_dia", "resumen_features")), recursive = TRUE)

features_cluster_dia <- data.table::copy(res$features_cluster_dia)
features_cluster_dia[, version_cluster := target_version_cluster]

arrow::write_dataset(
  features_cluster_dia,
  path = file.path(out_base, "features_cluster_dia"),
  format = "parquet",
  partitioning = c("version_cluster", "anio", "anio_mes"),
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

resumen <- data.table::copy(res$resumen)
resumen[, version_cluster := target_version_cluster]

arrow::write_dataset(
  resumen,
  path = file.path(out_base, "resumen_features"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

################################
### Salida de control
print(data.table::data.table(
  version_cluster = target_version_cluster,
  ventanas_dias = paste(ventanas_dias, collapse = ",")
))
print(resumen)
print(features_cluster_dia[, .N, by = tuvo_reclamo])
print(summary(features_cluster_dia$dias_desde_ultimo_reclamo))
print(summary(features_cluster_dia$dias_historia_observada_cluster))
print(features_cluster_dia[, .N, by = sin_reclamo_previo_observado])
