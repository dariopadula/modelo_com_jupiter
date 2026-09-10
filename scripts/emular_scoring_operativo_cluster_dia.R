library(arrow)
library(data.table)

source("funciones/modelos_utils.R")
source("funciones/scoring_operativo_utils.R")

################################
### Parametros
path_features <- Sys.getenv(
  "PATH_FEATURES",
  unset = "data/processed/modelo_cluster_dia/features_cluster_dia"
)
path_levante <- Sys.getenv("PATH_LEVANTE", unset = "data/parquet/levante")
path_com <- Sys.getenv("PATH_COM", unset = "data/parquet/com")
path_modelo <- Sys.getenv(
  "PATH_MODELO",
  unset = "data/processed/modelos/logistico_cluster_dia_reducido_reclamos_d2/modelo_logistico_reducido.rds"
)
out_base <- Sys.getenv("OUT_BASE_APP", unset = "data/processed/app_emulacion")

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
modelo_id <- Sys.getenv("MODELO_ID", unset = "logistico_reducido_d2")
version_modelo <- Sys.getenv("VERSION_MODELO", unset = "v2026_05_25")
target_col <- "tuvo_reclamo"

fecha_base_hasta <- data.table::as.IDate(Sys.getenv("FECHA_BASE_HASTA", unset = "2025-12-31"))
fecha_actualizar_hasta <- data.table::as.IDate(Sys.getenv("FECHA_ACTUALIZAR_HASTA", unset = NA_character_))
hora_corte_levantes <- Sys.getenv("HORA_CORTE_LEVANTES", unset = "01:00:00")
rezago_reclamos_dias <- as.integer(Sys.getenv("REZAGO_RECLAMOS_DIAS", unset = "2"))
forzar_reproceso <- tolower(Sys.getenv("FORZAR_REPROCESO", unset = "FALSE")) %in% c("true", "1", "si")

fecha_fuente_levante_hasta <- data.table::as.IDate(Sys.getenv("FECHA_FUENTE_LEVANTE_HASTA", unset = NA_character_))
fecha_com_cerrada_hasta <- data.table::as.IDate(Sys.getenv("FECHA_COM_CERRADA_HASTA", unset = NA_character_))

cortes_top <- c(0.01, 0.05, 0.10, 0.20)
timestamp_ejecucion <- Sys.time()

out_predicciones <- file.path(out_base, "predicciones_operativas_cluster_dia")
out_control <- file.path(out_base, "control_scoring")
out_metricas <- file.path(out_base, "metricas_diarias")

if (is.na(fecha_actualizar_hasta)) {
  stop("Debe definir FECHA_ACTUALIZAR_HASTA")
}
if (is.na(fecha_base_hasta)) {
  stop("Debe definir FECHA_BASE_HASTA")
}
if (fecha_actualizar_hasta <= fecha_base_hasta) {
  stop("FECHA_ACTUALIZAR_HASTA debe ser mayor que FECHA_BASE_HASTA")
}

################################
### Cargo modelo y datos
modelo <- readRDS(path_modelo)
features_modelo <- modelo$features_modelo
coef_pred <- modelo$coeficientes_prediccion
prep <- modelo$prep

datos <- as.data.table(arrow::open_dataset(path_features, format = "parquet"))

if (!is.na(target_version_cluster) && target_version_cluster != "") {
  datos <- datos[version_cluster == target_version_cluster]
} else {
  versiones <- sort(unique(datos$version_cluster))
  target_version_cluster <- versiones[length(versiones)]
  datos <- datos[version_cluster == target_version_cluster]
}

datos[, dia := data.table::as.IDate(dia)]
datos <- aplicar_rezago_historia_reclamos(
  datos,
  rezago_reclamos_dias = rezago_reclamos_dias
)
datos <- agregar_features_logistico_reducido(datos)

faltantes <- setdiff(c(target_col, "cluster_id", "dia", "anio_mes", features_modelo), names(datos))
if (length(faltantes) > 0L) {
  stop("Faltan columnas para scoring operativo: ", paste(faltantes, collapse = ", "))
}

################################
### Frescura de fuentes
levante <- as.data.table(arrow::open_dataset(path_levante, format = "parquet"))
com <- as.data.table(arrow::open_dataset(path_com, format = "parquet"))

timestamp_max_levante <- max(as.POSIXct(levante$fecha_levante, tz = "America/Montevideo"), na.rm = TRUE)
timestamp_max_com <- max(as.POSIXct(com$fecha_de_reclamo, tz = "America/Montevideo"), na.rm = TRUE)

if (!is.na(fecha_fuente_levante_hasta)) {
  timestamp_max_levante <- combinar_fecha_hora(fecha_fuente_levante_hasta, "23:59:59")
}
if (!is.na(fecha_com_cerrada_hasta)) {
  timestamp_max_com <- combinar_fecha_hora(fecha_com_cerrada_hasta, "23:59:59")
} else {
  fecha_com_cerrada_hasta <- data.table::as.IDate(as.Date(timestamp_max_com)) - 1L
}

################################
### Predicciones nuevas
dias_objetivo <- seq(fecha_base_hasta + 1L, fecha_actualizar_hasta, by = "day")
predicciones_existentes <- leer_dataset_si_existe(out_predicciones)

if (!is.null(predicciones_existentes)) {
  predicciones_existentes[, dia_objetivo := data.table::as.IDate(dia_objetivo)]
}

predicciones_nuevas <- list()
control <- list()

for (dia_i in dias_objetivo) {
  dia_i <- data.table::as.IDate(dia_i)
  timestamp_minimo_levante <- combinar_fecha_hora(dia_i, hora_corte_levantes)
  fecha_reclamos_usada_hasta <- dia_i - rezago_reclamos_dias

  existe_prediccion <- !is.null(predicciones_existentes) &&
    nrow(predicciones_existentes[
      dia_objetivo == dia_i &
        modelo_id == modelo_id &
        version_modelo == version_modelo
    ]) > 0L

  estado_levante <- fifelse(
    timestamp_max_levante >= timestamp_minimo_levante,
    "ok",
    "atrasado"
  )
  estado_com_features <- fifelse(
    fecha_com_cerrada_hasta >= fecha_reclamos_usada_hasta,
    "ok",
    "atrasado"
  )
  puede_generar <- estado_levante == "ok" && estado_com_features == "ok"

  if (existe_prediccion && !forzar_reproceso) {
    control[[length(control) + 1L]] <- data.table(
      dia_objetivo = dia_i,
      timestamp_ejecucion = timestamp_ejecucion,
      modelo_id = modelo_id,
      version_modelo = version_modelo,
      estado_prediccion = "ya_existia",
      motivo = "prediccion_existente",
      timestamp_minimo_levante = timestamp_minimo_levante,
      timestamp_max_levante = timestamp_max_levante,
      estado_levante = estado_levante,
      fecha_reclamos_usada_hasta = fecha_reclamos_usada_hasta,
      fecha_com_cerrada_hasta = fecha_com_cerrada_hasta,
      timestamp_max_com = timestamp_max_com,
      estado_com_features = estado_com_features,
      n_predicciones = 0L
    )
    next
  }

  if (!puede_generar) {
    control[[length(control) + 1L]] <- data.table(
      dia_objetivo = dia_i,
      timestamp_ejecucion = timestamp_ejecucion,
      modelo_id = modelo_id,
      version_modelo = version_modelo,
      estado_prediccion = "no_generada",
      motivo = paste(
        c(
          if (estado_levante != "ok") "levantes_no_actualizado",
          if (estado_com_features != "ok") "com_no_cerrado_para_features"
        ),
        collapse = ";"
      ),
      timestamp_minimo_levante = timestamp_minimo_levante,
      timestamp_max_levante = timestamp_max_levante,
      estado_levante = estado_levante,
      fecha_reclamos_usada_hasta = fecha_reclamos_usada_hasta,
      fecha_com_cerrada_hasta = fecha_com_cerrada_hasta,
      timestamp_max_com = timestamp_max_com,
      estado_com_features = estado_com_features,
      n_predicciones = 0L
    )
    next
  }

  scoring <- data.table::copy(datos[dia == dia_i])
  if (nrow(scoring) == 0L) {
    control[[length(control) + 1L]] <- data.table(
      dia_objetivo = dia_i,
      timestamp_ejecucion = timestamp_ejecucion,
      modelo_id = modelo_id,
      version_modelo = version_modelo,
      estado_prediccion = "no_generada",
      motivo = "sin_filas_scoring",
      timestamp_minimo_levante = timestamp_minimo_levante,
      timestamp_max_levante = timestamp_max_levante,
      estado_levante = estado_levante,
      fecha_reclamos_usada_hasta = fecha_reclamos_usada_hasta,
      fecha_com_cerrada_hasta = fecha_com_cerrada_hasta,
      timestamp_max_com = timestamp_max_com,
      estado_com_features = estado_com_features,
      n_predicciones = 0L
    )
    next
  }

  pred <- generar_predicciones_logistico_operativo(
    scoring = scoring,
    modelo = modelo,
    timestamp_corte_features = timestamp_minimo_levante,
    timestamp_ejecucion = timestamp_ejecucion,
    modelo_id = modelo_id,
    version_modelo = version_modelo,
    version_cluster = target_version_cluster,
    fecha_reclamos_usada_hasta = fecha_reclamos_usada_hasta,
    timestamp_max_levante = timestamp_max_levante,
    timestamp_max_com = timestamp_max_com
  )

  predicciones_nuevas[[length(predicciones_nuevas) + 1L]] <- pred
  control[[length(control) + 1L]] <- data.table(
    dia_objetivo = dia_i,
    timestamp_ejecucion = timestamp_ejecucion,
    modelo_id = modelo_id,
    version_modelo = version_modelo,
    estado_prediccion = "generada",
    motivo = "ok",
    timestamp_minimo_levante = timestamp_minimo_levante,
    timestamp_max_levante = timestamp_max_levante,
    estado_levante = estado_levante,
    fecha_reclamos_usada_hasta = fecha_reclamos_usada_hasta,
    fecha_com_cerrada_hasta = fecha_com_cerrada_hasta,
    timestamp_max_com = timestamp_max_com,
    estado_com_features = estado_com_features,
    n_predicciones = nrow(pred)
  )
}

predicciones_nuevas <- data.table::rbindlist(predicciones_nuevas, fill = TRUE)
control <- data.table::rbindlist(control, fill = TRUE)

################################
### Combino acumulado y cierro observados
predicciones_final <- data.table::rbindlist(
  list(predicciones_existentes, predicciones_nuevas),
  fill = TRUE
)

if (nrow(predicciones_final) > 0L) {
  if (forzar_reproceso) {
    data.table::setorder(predicciones_final, dia_objetivo, modelo_id, version_modelo, cluster_id, -timestamp_ejecucion)
    predicciones_final <- unique(
      predicciones_final,
      by = c("dia_objetivo", "modelo_id", "version_modelo", "cluster_id")
    )
  }

  predicciones_final <- actualizar_observados_operativos(
    predicciones = predicciones_final,
    datos_observados = datos,
    fecha_com_cerrada_hasta = fecha_com_cerrada_hasta,
    target_col = target_col
  )
}

metricas_diarias <- calcular_metricas_diarias_operativas(predicciones_final, cortes_top)

################################
### Guardo resultados
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)

if (nrow(predicciones_final) > 0L) {
  escribir_dataset_reemplazo(
    predicciones_final,
    out_predicciones,
    partitioning = c("modelo_id", "version_modelo", "anio_mes")
  )
}

if (nrow(control) > 0L) {
  control_existente <- leer_dataset_si_existe(out_control)
  control_final <- data.table::rbindlist(list(control_existente, control), fill = TRUE)
  escribir_dataset_reemplazo(
    control_final,
    out_control,
    partitioning = c("modelo_id", "version_modelo")
  )
}

if (nrow(metricas_diarias) > 0L) {
  escribir_dataset_reemplazo(
    metricas_diarias,
    out_metricas,
    partitioning = c("modelo_id", "version_modelo")
  )
}

################################
### Salida de control
print(data.table(
  fecha_base_hasta = fecha_base_hasta,
  fecha_actualizar_hasta = fecha_actualizar_hasta,
  modelo_id = modelo_id,
  version_modelo = version_modelo,
  version_cluster = target_version_cluster,
  rezago_reclamos_dias = rezago_reclamos_dias,
  hora_corte_levantes = hora_corte_levantes,
  timestamp_max_levante = timestamp_max_levante,
  fecha_com_cerrada_hasta = fecha_com_cerrada_hasta,
  timestamp_max_com = timestamp_max_com,
  predicciones_nuevas = nrow(predicciones_nuevas),
  predicciones_acumuladas = nrow(predicciones_final)
))
print(control)
if (nrow(metricas_diarias) > 0L) {
  print(metricas_diarias)
}
