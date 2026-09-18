library(arrow)
library(data.table)
library(dplyr)

source("funciones/splits_temporales.R")

path_contrato <- "config/splits_reevaluacion_2026.csv"
path_calendario_split <- paste0(
  "data/processed/features_compartidas/",
  "calendario_splits_reevaluacion_2026.parquet"
)
path_metadata <- paste0(
  "data/processed/features_compartidas/",
  "metadata_splits_reevaluacion_2026.csv"
)

contrato <- leer_contrato_splits(path_contrato)
calendario <- as.data.table(arrow::read_parquet(path_calendario_split))
calendario[, dia := as.IDate(dia)]
metadata <- fread(path_metadata)

if (anyDuplicated(calendario$dia)) stop("Hay dias duplicados")
if (!identical(
  calendario$dia,
  seq(min(calendario$dia), max(calendario$dia), by = "day")
)) stop("El calendario congelado no es continuo")
if (calendario[is.na(split), .N]) stop("Hay dias sin split")

esperado <- asignar_split_congelado(
  calendario[, .(dia)],
  contrato = contrato
)
if (!identical(calendario$split, esperado$split) ||
    !identical(calendario$version_split, esperado$version_split)) {
  stop("El calendario materializado no coincide con el contrato")
}

duraciones <- contrato[, .(
  split,
  n_dias = as.integer(fecha_hasta - fecha_desde) + 1L
)]
duraciones_esperadas <- data.table(
  split = c("contexto", "entrenamiento", "validacion", "test"),
  n_dias = c(90L, 365L, 91L, 76L)
)
if (!identical(duraciones, duraciones_esperadas)) {
  stop("Las duraciones no coinciden con el diseno congelado")
}

permisos <- contrato[, .(
  split, uso_permitido, puede_ajustar, puede_seleccionar,
  puede_reportar_metricas_ahora, estado
)]
permisos_esperados <- data.table(
  split = c("contexto", "entrenamiento", "validacion", "test"),
  uso_permitido = c(
    "historia_previa", "ajuste_modelos", "comparacion_candidatos",
    "evaluacion_final_unica"
  ),
  puede_ajustar = c(FALSE, TRUE, FALSE, FALSE),
  puede_seleccionar = c(FALSE, FALSE, TRUE, FALSE),
  puede_reportar_metricas_ahora = c(FALSE, TRUE, TRUE, FALSE),
  estado = c("contexto", "abierto", "abierto", "sellado")
)
if (!identical(permisos, permisos_esperados)) {
  stop("Los permisos no coinciden con el contrato congelado")
}

test <- contrato[split == "test"]
if (test$fecha_desde != as.IDate("2026-07-01") ||
    test$fecha_hasta != as.IDate("2026-09-14") ||
    test$estado != "sellado" || test$puede_reportar_metricas_ahora) {
  stop("El test puro no conserva el contrato acordado")
}

md5_actual <- unname(tools::md5sum(path_contrato))
if (uniqueN(metadata$contrato_md5) != 1L ||
    metadata$contrato_md5[[1L]] != md5_actual) {
  stop("El checksum del contrato no coincide")
}

paths_datos <- c(
  cluster_dia = "data/processed/modelo_cluster_dia/features_cluster_dia",
  segmento_dia = "data/processed/features_compartidas/segmento_dia",
  zona_limpia = "data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia"
)
cobertura <- rbindlist(lapply(names(paths_datos), function(nombre) {
  rango <- as.data.table(as.data.frame(
    arrow::open_dataset(paths_datos[[nombre]], format = "parquet") |>
      dplyr::summarise(fecha_min = min(dia), fecha_max = max(dia)) |>
      dplyr::collect()
  ))
  rango[, dataset := nombre]
  rango
}), use.names = TRUE)
cobertura[, `:=`(
  fecha_min = as.IDate(fecha_min),
  fecha_max = as.IDate(fecha_max)
)]
if (cobertura[fecha_min < min(contrato$fecha_desde) |
              fecha_max > max(contrato$fecha_hasta), .N]) {
  stop("Hay datasets fuera del calendario congelado")
}
if (cobertura[fecha_max != as.IDate("2026-09-14"), .N]) {
  stop("Alguna familia no llega al final del test congelado")
}

controles <- data.table(
  control = c(
    "contrato_contiguo",
    "calendario_sin_duplicados",
    "duraciones_congeladas",
    "permisos_congelados",
    "test_sellado",
    "checksum_contrato",
    "cobertura_familias"
  ),
  estado = "OK"
)
print(controles)
print(metadata[order(orden)])
print(cobertura[order(dataset)])
