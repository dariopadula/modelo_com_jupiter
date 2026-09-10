library(data.table)

fecha_desde <- as.IDate(Sys.getenv("INUMET_FECHA_DESDE", "2025-01-01"))
fecha_hasta_env <- Sys.getenv("INUMET_FECHA_HASTA", "")
fecha_hasta <- if (nzchar(fecha_hasta_env)) as.IDate(fecha_hasta_env) else Sys.Date()

estacion_nombre_fuente <- Sys.getenv("INUMET_ESTACION_NOMBRE_FUENTE", "Aeropuerto Melilla G3")
estacion_id_salida <- as.integer(Sys.getenv("INUMET_ESTACION_ID", "608"))
estacion_nombre_salida <- Sys.getenv("INUMET_ESTACION_NOMBRE", "Melilla G3")

raw_dir <- file.path("data", "raw", "inumet", "datos_abiertos")
processed_dir <- file.path("data", "processed", "clima", "inumet_melilla_g3")
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)

path_temperatura <- file.path(raw_dir, "inumet_temperatura_del_aire.csv")
path_precipitacion <- file.path(raw_dir, "inumet_precipitacion_acumulada_horaria.csv")

leer_csv_inumet <- function(path, columna_valor_fuente, columna_valor_salida) {
  if (!file.exists(path)) {
    stop("No existe archivo INUMET: ", path)
  }

  dt <- data.table::fread(
    path,
    sep = ";",
    na.strings = c("", "NA"),
    encoding = "UTF-8"
  )

  columnas_necesarias <- c("fecha", "estacion_id", columna_valor_fuente)
  faltantes <- setdiff(columnas_necesarias, names(dt))
  if (length(faltantes) > 0L) {
    stop("Faltan columnas en ", path, ": ", paste(faltantes, collapse = ", "))
  }

  dt <- dt[
    !is.na(fecha) &
      !is.na(estacion_id) &
      estacion_id == estacion_nombre_fuente
  ]

  dt[, fecha_hora := as.POSIXct(
    fecha,
    format = "%Y-%m-%d %H:%M",
    tz = "America/Montevideo"
  )]
  dt[, dia := as.IDate(fecha_hora, tz = "America/Montevideo")]
  dt <- dt[dia >= fecha_desde & dia <= fecha_hasta]

  setnames(dt, columna_valor_fuente, columna_valor_salida)
  dt[, (columna_valor_salida) := as.numeric(get(columna_valor_salida))]

  dt[, .(fecha_hora, dia, valor = get(columna_valor_salida))]
}

temperatura <- leer_csv_inumet(
  path = path_temperatura,
  columna_valor_fuente = "temp_aire",
  columna_valor_salida = "temperatura_aire_c"
)
setnames(temperatura, "valor", "temperatura_aire_c")

precipitacion <- leer_csv_inumet(
  path = path_precipitacion,
  columna_valor_fuente = "precip_horario",
  columna_valor_salida = "precipitacion_acum_horaria_mm"
)
setnames(precipitacion, "valor", "precipitacion_acum_horaria_mm")

clima_horario <- merge(
  temperatura,
  precipitacion,
  by = c("fecha_hora", "dia"),
  all = TRUE
)
setorder(clima_horario, fecha_hora)

clima_horario[, `:=`(
  estacion_id = estacion_id_salida,
  estacion_nombre = estacion_nombre_salida
)]
setcolorder(clima_horario, c(
  "estacion_id",
  "estacion_nombre",
  "fecha_hora",
  "dia",
  "temperatura_aire_c",
  "precipitacion_acum_horaria_mm"
))

clima_diario <- clima_horario[
  ,
  .(
    temp_media_c = mean(temperatura_aire_c, na.rm = TRUE),
    temp_min_c = min(temperatura_aire_c, na.rm = TRUE),
    temp_max_c = max(temperatura_aire_c, na.rm = TRUE),
    precipitacion_mm = sum(precipitacion_acum_horaria_mm, na.rm = TRUE),
    horas_temp_validas = sum(!is.na(temperatura_aire_c)),
    horas_prec_validas = sum(!is.na(precipitacion_acum_horaria_mm))
  ),
  by = .(estacion_id, estacion_nombre, dia)
]

for (col in c("temp_media_c", "temp_min_c", "temp_max_c", "precipitacion_mm")) {
  idx <- which(is.nan(clima_diario[[col]]) | is.infinite(clima_diario[[col]]))
  if (length(idx) > 0L) set(clima_diario, idx, col, NA_real_)
}

clima_diario[, llovio := precipitacion_mm > 0]
clima_diario[, precipitacion_max_hora_mm := clima_horario[
  .SD,
  on = .(estacion_id, estacion_nombre, dia),
  max(precipitacion_acum_horaria_mm, na.rm = TRUE),
  by = .EACHI
]$V1]
clima_diario[, horas_con_lluvia := clima_horario[
  .SD,
  on = .(estacion_id, estacion_nombre, dia),
  sum(precipitacion_acum_horaria_mm > 0, na.rm = TRUE),
  by = .EACHI
]$V1]
clima_diario[is.infinite(precipitacion_max_hora_mm), precipitacion_max_hora_mm := NA_real_]
clima_diario[, temp_rango_c := temp_max_c - temp_min_c]

clima_features <- data.table(
  estacion_id = estacion_id_salida,
  estacion_nombre = estacion_nombre_salida,
  dia = seq(min(clima_diario$dia) + 1L, max(clima_diario$dia), by = "day")
)

clima_features <- clima_diario[
  clima_features,
  on = .(estacion_id, estacion_nombre, dia = dia),
  .(
    estacion_id = i.estacion_id,
    estacion_nombre = i.estacion_nombre,
    dia = i.dia
  )
]

agregar_lag_dia <- function(features, diario) {
  d1 <- copy(diario)
  d1[, dia := dia + 1L]
  d1 <- d1[
    ,
    .(
      estacion_id,
      estacion_nombre,
      dia,
      precipitacion_d1_mm = precipitacion_mm,
      precipitacion_max_hora_d1_mm = precipitacion_max_hora_mm,
      horas_con_lluvia_d1 = horas_con_lluvia,
      llovio_d1 = llovio,
      temp_media_d1_c = temp_media_c,
      temp_min_d1_c = temp_min_c,
      temp_max_d1_c = temp_max_c,
      temp_rango_d1_c = temp_rango_c,
      horas_temp_validas_d1 = horas_temp_validas,
      horas_prec_validas_d1 = horas_prec_validas
    )
  ]

  d1[features, on = .(estacion_id, estacion_nombre, dia)]
}

agregar_ventana_3d <- function(features, diario) {
  rbindlist(lapply(seq_len(nrow(features)), function(i) {
    dia_obj <- features$dia[i]
    ventana <- diario[dia >= dia_obj - 3L & dia <= dia_obj - 1L]
    data.table(
      estacion_id = features$estacion_id[i],
      estacion_nombre = features$estacion_nombre[i],
      dia = dia_obj,
      precipitacion_3d_mm = sum(ventana$precipitacion_mm, na.rm = TRUE),
      precipitacion_max_hora_3d_mm = max(ventana$precipitacion_max_hora_mm, na.rm = TRUE),
      dias_con_lluvia_3d = sum(ventana$llovio, na.rm = TRUE),
      temp_media_3d_c = mean(ventana$temp_media_c, na.rm = TRUE),
      temp_min_3d_c = min(ventana$temp_min_c, na.rm = TRUE),
      temp_max_3d_c = max(ventana$temp_max_c, na.rm = TRUE),
      horas_temp_validas_3d = sum(ventana$horas_temp_validas, na.rm = TRUE),
      horas_prec_validas_3d = sum(ventana$horas_prec_validas, na.rm = TRUE)
    )
  }), fill = TRUE)
}

clima_features <- agregar_lag_dia(clima_features, clima_diario)
clima_features_3d <- agregar_ventana_3d(clima_features, clima_diario)
clima_features <- clima_features_3d[
  clima_features,
  on = .(estacion_id, estacion_nombre, dia)
]

for (col in c(
  "precipitacion_max_hora_3d_mm",
  "temp_media_3d_c",
  "temp_min_3d_c",
  "temp_max_3d_c"
)) {
  idx <- which(is.nan(clima_features[[col]]) | is.infinite(clima_features[[col]]))
  if (length(idx) > 0L) set(clima_features, idx, col, NA_real_)
}

setcolorder(clima_features, c(
  "estacion_id",
  "estacion_nombre",
  "dia",
  "precipitacion_d1_mm",
  "precipitacion_max_hora_d1_mm",
  "horas_con_lluvia_d1",
  "llovio_d1",
  "precipitacion_3d_mm",
  "precipitacion_max_hora_3d_mm",
  "dias_con_lluvia_3d",
  "temp_media_d1_c",
  "temp_min_d1_c",
  "temp_max_d1_c",
  "temp_rango_d1_c",
  "temp_media_3d_c",
  "temp_min_3d_c",
  "temp_max_3d_c",
  "horas_temp_validas_d1",
  "horas_prec_validas_d1",
  "horas_temp_validas_3d",
  "horas_prec_validas_3d"
))

cobertura <- rbindlist(list(
  data.table(
    variable_id = "temperatura_aire",
    archivo = basename(path_temperatura),
    estacion_fuente = estacion_nombre_fuente,
    filas_horarias = nrow(temperatura),
    desde = as.character(min(temperatura$dia)),
    hasta = as.character(max(temperatura$dia))
  ),
  data.table(
    variable_id = "precipitacion_acum_horaria",
    archivo = basename(path_precipitacion),
    estacion_fuente = estacion_nombre_fuente,
    filas_horarias = nrow(precipitacion),
    desde = as.character(min(precipitacion$dia)),
    hasta = as.character(max(precipitacion$dia))
  )
), fill = TRUE)

data.table::fwrite(
  clima_horario,
  file.path(processed_dir, "clima_inumet_melilla_g3_horario.csv")
)
data.table::fwrite(
  clima_diario,
  file.path(processed_dir, "clima_inumet_melilla_g3_diario.csv")
)
data.table::fwrite(
  clima_features,
  file.path(processed_dir, "clima_inumet_melilla_g3_features_diarias.csv")
)
data.table::fwrite(cobertura, file.path(processed_dir, "cobertura_anual.csv"))

metadata <- data.table(
  fuente = "INUMET datos abiertos CSV local",
  path_temperatura = path_temperatura,
  path_precipitacion = path_precipitacion,
  estacion_id = estacion_id_salida,
  estacion_nombre = estacion_nombre_salida,
  estacion_nombre_fuente = estacion_nombre_fuente,
  fecha_desde = as.character(fecha_desde),
  fecha_hasta = as.character(fecha_hasta),
  variables = "Temperatura del Aire; Precipitacion Acumulada Horaria",
  advertencia = "Datos crudos sin validacion publicados por INUMET; CSV local descargado manualmente"
)
data.table::fwrite(metadata, file.path(processed_dir, "metadata.csv"))

print(metadata)
print(clima_diario[, .(
  dias = .N,
  desde = min(dia),
  hasta = max(dia),
  temp_media_c = round(mean(temp_media_c, na.rm = TRUE), 2),
  precipitacion_total_mm = round(sum(precipitacion_mm, na.rm = TRUE), 2),
  dias_temp_incompleta = sum(horas_temp_validas < 24),
  dias_prec_incompleta = sum(horas_prec_validas < 24)
)])
