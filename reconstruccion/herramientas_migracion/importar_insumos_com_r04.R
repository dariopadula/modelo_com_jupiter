# Importa un bloque historico preparado para validar R04; no es ingesta diaria.
# Entradas: raiz original explicita. Salida: insumos RDS propios, limitados a la
# muestra R03.
all_args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", all_args, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Indicar raiz original")
old <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
.libPaths(c("C:/Users/dario/AppData/Local/R/win-library/4.5", .libPaths()))
for (package in c("arrow", "dplyr", "data.table")) {
  if (!requireNamespace(package, quietly = TRUE))
    stop("Falta paquete: ", package)
}
out <- file.path(root, "runtime/r04_com")
if (file.exists(file.path(out, "insumos.rds"))) stop("Insumos R04 ya existen; no sobrescribir")
reference <- readRDS(file.path(root, "runtime/r03_com/referencia_predicciones.rds"))
ids <- reference$cluster_id
from <- as.Date("2025-01-01")
through <- as.Date("2026-03-31")
map <- arrow::open_dataset(file.path(old, "data/processed/cluster_update_check/contenedor_posicion_cluster_actual"))
map <- as.data.frame(dplyr::collect(dplyr::filter(map, version_cluster == "v2026_05_25")))
containers <- unique(map$levante_contenedor_id[map$cluster_id %in% ids])
map <- map[map$levante_contenedor_id %in% containers, ]
levante <- arrow::open_dataset(file.path(old, "data/parquet/levante"))
levante <- dplyr::collect(dplyr::filter(levante, levante_contenedor_id %in% !!containers,
  dia >= !!from, dia <= !!through))
claims <- arrow::open_dataset(file.path(old, "data/processed/com_contenedor_cluster/asignaciones_com"))
claims <- as.data.frame(dplyr::collect(dplyr::filter(claims, cluster_id %in% !!ids, dia >=
  !!from, dia <= !!through, version_cluster == "v2026_05_25", estado_asignacion_com %in%
  c("asignado", "revision"))))
# No se pasan etiquetas al asignador: se reconstruyen desde evento y coordenadas.
com <- claims[c("id", "dia", "incidente", "x_com", "y_com")]
names(com)[names(com) == "x_com"] <- "x"
names(com)[names(com) == "y_com"] <- "y"
expected <- arrow::open_dataset(file.path(old, "data/processed/modelo_cluster_dia/features_cluster_dia"))
expected <- dplyr::collect(dplyr::filter(expected, cluster_id %in% !!ids, dia >= !!from,
  dia <= !!through, version_cluster == "v2026_05_25", cluster_existente_dia == TRUE))
if (nrow(levante) > 200000L || nrow(claims) > 50000L) stop("Bloque excede el limite rapido previsto")
inputs <- list(levante = levante, com = com, position_map = map, from = from, through = through,
  target_clusters = ids, marks = list(source_id = "snapshot_historico_r04_local", timezone = "America/Montevideo",
    complete_through = NULL, available_through_timestamp = NULL), scope = "Eventos asignados previamente al bloque; no valida cobertura espacial fuera de el")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
saveRDS(inputs, file.path(out, "insumos.rds"))
saveRDS(expected, file.path(out, "features_referencia.rds"))
saveRDS(claims, file.path(out, "asignaciones_referencia.rds"))
cat("R04_INSUMOS_OK:", nrow(levante), "levantes;", nrow(com), "eventos;", nrow(expected),
  "features\n")
