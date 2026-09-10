library(arrow)
library(data.table)
library(dplyr)

path_predicciones <- Sys.getenv(
  "PATH_PREDICCIONES_APP",
  unset = "app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia"
)
path_pred_dia <- Sys.getenv(
  "PATH_PREDICCIONES_AGREGADAS_DIA",
  unset = "outputs/comparacion_poda_xgboost_com/predicciones_diarias.csv"
)
path_pred_barrio <- Sys.getenv(
  "PATH_PREDICCIONES_AGREGADAS_BARRIO",
  unset = "outputs/comparacion_poda_xgboost_com/predicciones_barrio_dia.csv"
)
out_base <- Sys.getenv(
  "OUT_BASE_APP_HISTORICO",
  unset = "app_operativa_v2/data/historico"
)
escenario_com <- Sys.getenv("ESCENARIO_COM_HISTORICO", unset = "P3_compacto")
sobrescribir <- identical(Sys.getenv("SOBRESCRIBIR", unset = "0"), "1")

validar_fuente <- function(path, tipo = c("directorio", "archivo")) {
  tipo <- match.arg(tipo)
  existe <- if (tipo == "directorio") dir.exists(path) else file.exists(path)
  if (!existe) stop("No existe la fuente requerida: ", path)
}

validar_fuente(path_predicciones, "directorio")
validar_fuente(path_pred_dia, "archivo")
validar_fuente(path_pred_barrio, "archivo")

if (dir.exists(out_base) && !sobrescribir) {
  stop(
    "La salida ya existe: ", out_base,
    ". Use SOBRESCRIBIR=1 para reconstruirla."
  )
}

pred_dia <- fread(path_pred_dia)[escenario == escenario_com]
pred_barrio <- fread(path_pred_barrio)[escenario == escenario_com]

if (!nrow(pred_dia) || !nrow(pred_barrio)) {
  stop("No hay predicciones agregadas para el escenario ", escenario_com)
}

pred_dia[, dia_objetivo := as.IDate(dia_objetivo)]
pred_barrio[, dia_objetivo := as.IDate(dia_objetivo)]

clusters_evaluados_dia <- pred_barrio[, .(
  clusters_evaluados = as.integer(sum(n_clusters))
), by = dia_objetivo]
pred_dia <- clusters_evaluados_dia[pred_dia, on = "dia_objetivo"]

serie_montevideo <- pred_dia[, .(
  dia_objetivo,
  nivel_territorial = "montevideo",
  territorio_id = "montevideo",
  territorio_nombre = "Montevideo",
  clusters_estimados = as.numeric(predicho),
  clusters_observados = as.integer(observado),
  clusters_evaluados = as.integer(clusters_evaluados),
  escenario,
  split_modelo,
  estado_observacion = "cerrado"
)]

serie_barrio <- pred_barrio[, .(
  dia_objetivo,
  nivel_territorial = "barrio",
  territorio_id = as.character(barrio),
  territorio_nombre = as.character(barrio),
  clusters_estimados = as.numeric(predicho),
  clusters_observados = as.integer(observado),
  clusters_evaluados = as.integer(n_clusters),
  escenario,
  split_modelo,
  estado_observacion = "cerrado"
)]

serie_historica <- rbindlist(
  list(serie_montevideo, serie_barrio),
  use.names = TRUE
)
setorder(serie_historica, dia_objetivo, nivel_territorial, territorio_nombre)

duplicados_serie <- serie_historica[, .N, by = .(
  dia_objetivo, nivel_territorial, territorio_id, escenario
)][N > 1L]
if (nrow(duplicados_serie)) {
  stop("La serie historica contiene claves duplicadas")
}

control_barrio <- serie_barrio[, .(
  observado_barrios = sum(clusters_observados),
  estimado_barrios = sum(clusters_estimados)
), by = dia_objetivo]
control_ciudad <- control_barrio[serie_montevideo, on = "dia_objetivo"]
if (any(control_ciudad$observado_barrios != control_ciudad$clusters_observados)) {
  stop("Los observados por barrio no suman el total de Montevideo")
}
if (any(abs(
  control_ciudad$estimado_barrios - control_ciudad$clusters_estimados
) > 1e-6)) {
  stop("Las estimaciones por barrio no suman el total de Montevideo")
}

ds_pred <- open_dataset(path_predicciones, format = "parquet")
columnas_detalle <- c(
  "cluster_id", "dia_objetivo", "modelo_id", "version_modelo",
  "version_cluster", "pred_prob", "ranking_dia", "percentil_riesgo",
  "estado_prediccion", "estado_periodo_app", "estado_observacion",
  "tuvo_reclamo_observado", "n_reclamos_observado",
  "hay_zl_visita_efectiva", "problema_zl_observado",
  "n_zl_problema_comparable", "estado_observacion_zl",
  "timestamp_ejecucion"
)
faltantes <- setdiff(columnas_detalle, names(ds_pred))
if (length(faltantes)) {
  stop("Faltan columnas en el detalle fuente: ", paste(faltantes, collapse = ", "))
}
detalle <- ds_pred |>
  select(all_of(columnas_detalle))

staging <- paste0(out_base, ".staging")
if (dir.exists(staging)) unlink(staging, recursive = TRUE)
dir.create(staging, recursive = TRUE, showWarnings = FALSE)

write_dataset(
  serie_historica,
  path = file.path(staging, "serie_historica_com"),
  format = "parquet",
  compression = "zstd",
  existing_data_behavior = "overwrite"
)
write_dataset(
  detalle,
  path = file.path(staging, "detalle_cluster_dia"),
  format = "parquet",
  partitioning = c("dia_objetivo", "modelo_id"),
  compression = "zstd",
  existing_data_behavior = "overwrite",
  basename_template = "part-{i}.parquet"
)

detalle_publicado <- open_dataset(
  file.path(staging, "detalle_cluster_dia"),
  format = "parquet",
  partitioning = hive_partition(
    dia_objetivo = date32(),
    modelo_id = utf8()
  )
)
resumen_detalle <- detalle_publicado |>
  summarise(
    filas = n(),
    dias = n_distinct(dia_objetivo),
    clusters = n_distinct(cluster_id),
    modelos = n_distinct(modelo_id),
    desde = min(dia_objetivo, na.rm = TRUE),
    hasta = max(dia_objetivo, na.rm = TRUE)
  ) |>
  collect() |>
  as.data.table()

if (resumen_detalle$filas[[1]] <= 0L || resumen_detalle$dias[[1]] <= 0L) {
  stop("El detalle publicado quedo vacio")
}

fecha_prueba <- as.Date(resumen_detalle$hasta[[1]])
lectura_prueba <- detalle_publicado |>
  filter(dia_objetivo == !!fecha_prueba, modelo_id == "com_reclamo") |>
  collect() |>
  as.data.table()
if (!nrow(lectura_prueba) || any(as.Date(lectura_prueba$dia_objetivo) != fecha_prueba)) {
  stop("Fallo la lectura selectiva de una particion diaria")
}

resumen_publicacion <- data.table(
  tabla = c("serie_historica_com", "detalle_cluster_dia"),
  filas = c(nrow(serie_historica), resumen_detalle$filas[[1]]),
  dias = c(uniqueN(serie_historica$dia_objetivo), resumen_detalle$dias[[1]]),
  desde = as.IDate(c(min(serie_historica$dia_objetivo), resumen_detalle$desde[[1]])),
  hasta = as.IDate(c(max(serie_historica$dia_objetivo), resumen_detalle$hasta[[1]])),
  escenario = c(escenario_com, NA_character_),
  particionamiento = c("sin particionar", "dia_objetivo/modelo_id")
)
fwrite(resumen_publicacion, file.path(staging, "resumen_publicacion.csv"))

if (dir.exists(out_base)) unlink(out_base, recursive = TRUE)
if (!file.rename(staging, out_base)) {
  stop("No se pudo publicar la salida desde staging")
}

print(resumen_publicacion)
cat("TABLAS_HISTORICAS_OK\n")
