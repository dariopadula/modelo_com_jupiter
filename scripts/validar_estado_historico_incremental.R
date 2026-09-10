library(arrow)
library(data.table)

source("funciones/scoring_operativo_utils.R")

################################
### Parametros
path_features <- Sys.getenv(
  "PATH_FEATURES",
  unset = "data/processed/modelo_cluster_dia/features_cluster_dia"
)
path_estado_inicial <- Sys.getenv(
  "PATH_ESTADO_INICIAL",
  unset = "data/processed/app_emulacion/estado_historico_cluster"
)
out_base <- Sys.getenv(
  "OUT_BASE_ESTADO_INCREMENTAL",
  unset = "data/processed/app_emulacion_estado_incremental"
)

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
fecha_actualizar_hasta <- data.table::as.IDate(Sys.getenv("FECHA_ACTUALIZAR_HASTA", unset = "2026-01-10"))
rezago_cierre_reclamos <- as.integer(Sys.getenv("REZAGO_CIERRE_RECLAMOS", unset = "1"))
target_col <- "tuvo_reclamo"

################################
### Cargo datos
datos <- as.data.table(arrow::open_dataset(path_features, format = "parquet"))
estado_inicial <- as.data.table(arrow::open_dataset(path_estado_inicial, format = "parquet"))

if (!is.na(target_version_cluster) && target_version_cluster != "") {
  datos <- datos[version_cluster == target_version_cluster]
  estado_inicial <- estado_inicial[version_cluster == target_version_cluster]
} else {
  versiones <- sort(unique(datos$version_cluster))
  target_version_cluster <- versiones[length(versiones)]
  datos <- datos[version_cluster == target_version_cluster]
  estado_inicial <- estado_inicial[version_cluster == target_version_cluster]
}

datos[, dia := data.table::as.IDate(dia)]
estado_inicial[, `:=`(
  fecha_estado = data.table::as.IDate(fecha_estado),
  fecha_reclamos_cerrada_hasta = data.table::as.IDate(fecha_reclamos_cerrada_hasta),
  fecha_inicio_observacion_cluster = data.table::as.IDate(fecha_inicio_observacion_cluster),
  fecha_ultimo_reclamo_cerrado = data.table::as.IDate(fecha_ultimo_reclamo_cerrado)
)]

fecha_estado_inicial <- unique(estado_inicial$fecha_estado)
fecha_reclamos_inicial <- unique(estado_inicial$fecha_reclamos_cerrada_hasta)
if (length(fecha_estado_inicial) != 1L) {
  stop("El estado inicial debe tener una unica fecha")
}
if (length(fecha_reclamos_inicial) != 1L) {
  stop("El estado inicial debe tener una unica fecha de cierre de reclamos")
}
if (fecha_actualizar_hasta <= fecha_estado_inicial) {
  stop("FECHA_ACTUALIZAR_HASTA debe ser posterior al estado inicial")
}

################################
### Actualizacion diaria incremental
estado_incremental <- data.table::copy(estado_inicial)
control_actualizaciones <- list()

for (dia_i in seq(fecha_estado_inicial + 1L, fecha_actualizar_hasta, by = "day")) {
  dia_i <- data.table::as.IDate(dia_i)
  fecha_reclamos_cerrada <- dia_i - rezago_cierre_reclamos

  tiempo <- system.time({
    estado_incremental <- actualizar_estado_historico_cluster(
      estado_anterior = estado_incremental,
      datos_nuevos_cluster_dia = datos[
        dia > min(fecha_estado_inicial, fecha_reclamos_inicial) &
          dia <= dia_i
      ],
      nueva_fecha_estado = dia_i,
      nueva_fecha_reclamos_cerrada_hasta = fecha_reclamos_cerrada,
      target_col = target_col
    )
  })

  control_actualizaciones[[length(control_actualizaciones) + 1L]] <- data.table(
    fecha_estado = dia_i,
    fecha_reclamos_cerrada_hasta = fecha_reclamos_cerrada,
    clusters = nrow(estado_incremental),
    clusters_activos = sum(estado_incremental$cluster_activo_fecha_estado == TRUE, na.rm = TRUE),
    segundos_actualizacion = as.numeric(tiempo[["elapsed"]])
  )
}

control_actualizaciones <- data.table::rbindlist(control_actualizaciones)

################################
### Reconstruccion completa de referencia
fecha_reclamos_final <- fecha_actualizar_hasta - rezago_cierre_reclamos
tiempo_completo <- system.time({
  estado_completo <- construir_estado_historico_cluster(
    datos_cluster_dia = datos,
    fecha_estado = fecha_actualizar_hasta,
    fecha_reclamos_cerrada_hasta = fecha_reclamos_final,
    target_col = target_col
  )
})

estado_incremental[, version_cluster := target_version_cluster]
estado_completo[, version_cluster := target_version_cluster]

################################
### Comparacion
columnas_comparar <- intersect(
  setdiff(names(estado_completo), "cluster_id"),
  names(estado_incremental)
)

inc <- data.table::copy(estado_incremental[, c("cluster_id", columnas_comparar), with = FALSE])
ref <- data.table::copy(estado_completo[, c("cluster_id", columnas_comparar), with = FALSE])
data.table::setnames(inc, columnas_comparar, paste0(columnas_comparar, "_inc"))
data.table::setnames(ref, columnas_comparar, paste0(columnas_comparar, "_ref"))
detalle <- merge(inc, ref, by = "cluster_id", all = TRUE)

comparacion <- data.table::rbindlist(lapply(columnas_comparar, function(col) {
  x <- detalle[[paste0(col, "_inc")]]
  y <- detalle[[paste0(col, "_ref")]]
  comparables <- !is.na(x) & !is.na(y)
  ambos_na <- is.na(x) & is.na(y)

  if (inherits(x, "Date") || inherits(x, "IDate")) x_cmp <- as.numeric(x) else x_cmp <- x
  if (inherits(y, "Date") || inherits(y, "IDate")) y_cmp <- as.numeric(y) else y_cmp <- y

  if (is.numeric(x_cmp) || is.integer(x_cmp) || is.logical(x_cmp)) {
    distintos <- comparables & abs(as.numeric(x_cmp) - as.numeric(y_cmp)) > 1e-8
    diff_abs <- abs(as.numeric(x_cmp) - as.numeric(y_cmp))
  } else {
    distintos <- comparables & as.character(x_cmp) != as.character(y_cmp)
    diff_abs <- rep(NA_real_, length(x_cmp))
  }

  data.table(
    variable = col,
    n_filas = length(x),
    n_iguales_na = sum(ambos_na),
    n_comparables = sum(comparables),
    n_distintos = sum(distintos, na.rm = TRUE),
    pct_distintos = fifelse(sum(comparables) > 0, sum(distintos, na.rm = TRUE) / sum(comparables), NA_real_),
    diff_abs_max = if (any(comparables) && any(!is.na(diff_abs[comparables]))) {
      max(diff_abs[comparables], na.rm = TRUE)
    } else {
      NA_real_
    }
  )
}))

resumen <- data.table(
  version_cluster = target_version_cluster,
  fecha_estado_inicial = fecha_estado_inicial,
  fecha_estado_final = fecha_actualizar_hasta,
  fecha_reclamos_cerrada_final = fecha_reclamos_final,
  clusters_incremental = nrow(estado_incremental),
  clusters_completo = nrow(estado_completo),
  variables_con_diferencias = sum(comparacion$n_distintos > 0, na.rm = TRUE),
  filas_variables_distintas = sum(comparacion$n_distintos, na.rm = TRUE),
  segundos_incremental_total = sum(control_actualizaciones$segundos_actualizacion),
  segundos_reconstruccion_completa = as.numeric(tiempo_completo[["elapsed"]])
)

################################
### Guardo resultados
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
escribir_dataset_reemplazo(
  estado_incremental,
  file.path(out_base, "estado_incremental"),
  partitioning = c("version_cluster", "fecha_estado")
)
escribir_dataset_reemplazo(
  estado_completo,
  file.path(out_base, "estado_completo_referencia"),
  partitioning = c("version_cluster", "fecha_estado")
)
escribir_dataset_reemplazo(
  comparacion,
  file.path(out_base, "comparacion_estado"),
  partitioning = NULL
)
escribir_dataset_reemplazo(
  control_actualizaciones,
  file.path(out_base, "control_actualizaciones"),
  partitioning = NULL
)
escribir_dataset_reemplazo(
  resumen,
  file.path(out_base, "resumen"),
  partitioning = NULL
)

################################
### Salida de control
print(resumen)
print(comparacion[order(-n_distintos)])
print(control_actualizaciones)
