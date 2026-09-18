library(arrow)
library(data.table)
library(dplyr)

fecha_corte <- as.IDate("2026-09-14")
out_dir <- "outputs/auditoria_actualizacion_202609"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

resumen_parquet <- function(path, fuente, fecha_col, id_col = NULL) {
  ds <- arrow::open_dataset(path, format = "parquet")
  cols <- unique(c(fecha_col, id_col, "anio_mes"))
  dt <- as.data.table(dplyr::collect(dplyr::select(ds, dplyr::all_of(intersect(cols, names(ds))))))
  fecha <- dt[[fecha_col]]

  if (inherits(fecha, "POSIXt")) {
    # Los snapshots locales guardan timestamps sin zona. La hora civil original
    # se recupera leyendo la representacion UTC, antes de asignar Montevideo.
    fecha_txt <- format(fecha, "%Y-%m-%d %H:%M:%OS", tz = "UTC")
  } else {
    fecha_txt <- as.character(fecha)
  }
  fecha_local <- as.POSIXct(fecha_txt, format = "%Y-%m-%d %H:%M:%OS", tz = "America/Montevideo")

  data.table(
    fuente = fuente,
    path = path,
    filas = nrow(dt),
    fecha_min = as.character(min(fecha_local, na.rm = TRUE)),
    fecha_max = as.character(max(fecha_local, na.rm = TRUE)),
    filas_despues_corte = sum(as.IDate(fecha_local) > fecha_corte, na.rm = TRUE),
    ids_distintos = if (is.null(id_col)) NA_integer_ else uniqueN(dt[[id_col]], na.rm = TRUE),
    filas_adicionales_ids_reutilizados = if (is.null(id_col)) NA_integer_ else nrow(dt) - uniqueN(dt[[id_col]], na.rm = TRUE),
    meses = paste(sort(unique(dt$anio_mes)), collapse = ",")
  )
}

normalizar_com_comparacion <- function(dt) {
  setDT(dt)
  for (col in intersect(c("fecha_de_reclamo", "fecha_resuelto"), names(dt))) {
    if (inherits(dt[[col]], "POSIXt")) {
      set(dt, j = col, value = format(dt[[col]], "%Y-%m-%d %H:%M:%S", tz = "UTC"))
    } else {
      set(dt, j = col, value = substr(as.character(dt[[col]]), 1L, 19L))
    }
  }
  dt[]
}

comparar_snapshots_mes <- function(path_nuevo, path_anterior, fuente) {
  nuevo_ds <- arrow::open_dataset(path_nuevo, format = "parquet")
  anterior_ds <- arrow::open_dataset(path_anterior, format = "parquet")
  meses <- sort(intersect(
    unique(dplyr::collect(dplyr::select(nuevo_ds, anio_mes))[[1L]]),
    unique(dplyr::collect(dplyr::select(anterior_ds, anio_mes))[[1L]])
  ))
  # El procesamiento consolidado ya estaba validado hasta 2025. Para esta
  # actualizacion se contrasta exhaustivamente el periodo potencialmente mutable.
  meses <- meses[meses >= 202601]

  rbindlist(lapply(meses, function(mes) {
    nuevo <- as.data.table(dplyr::collect(dplyr::filter(nuevo_ds, anio_mes == mes)))
    anterior <- as.data.table(dplyr::collect(dplyr::filter(anterior_ds, anio_mes == mes)))
    if (fuente == "COM") {
      nuevo <- normalizar_com_comparacion(nuevo)
      anterior <- normalizar_com_comparacion(anterior)
    }
    cols <- intersect(names(nuevo), names(anterior))
    setcolorder(nuevo, cols)
    setcolorder(anterior, cols)
    nuevo <- unique(nuevo)
    anterior <- unique(anterior)

    data.table(
      fuente = fuente,
      anio_mes = as.integer(mes),
      filas_nuevo = nrow(nuevo),
      filas_anterior = nrow(anterior),
      filas_solo_nuevo = nrow(fsetdiff(nuevo, anterior)),
      filas_solo_anterior = nrow(fsetdiff(anterior, nuevo)),
      identico = setequal(nuevo, anterior)
    )
  }))
}

archivos <- data.table(
  fuente = c("COM nuevo", "COM anterior", "Levantes nuevo", "Levantes anterior"),
  path = c(
    "data/paraprobar/datos_com.parquet",
    "data/paraprobar/datos_com_old.parquet",
    "data/paraprobar/datos_levante.parquet",
    "data/paraprobar/datos_levante_old.parquet"
  ),
  fecha_col = c("fecha_de_reclamo", "fecha_de_reclamo", "levante_fecha_levante", "levante_fecha_levante"),
  id_col = c("id", "id", NA_character_, NA_character_)
)

resumen <- rbindlist(lapply(seq_len(nrow(archivos)), function(i) {
  resumen_parquet(
    archivos$path[[i]], archivos$fuente[[i]], archivos$fecha_col[[i]],
    if (is.na(archivos$id_col[[i]])) NULL else archivos$id_col[[i]]
  )
}))

comparar_snapshots <- tolower(Sys.getenv("AUDITAR_COMPARACION_SNAPSHOTS", "true")) == "true"
if (comparar_snapshots) {
  comparacion <- rbindlist(list(
    comparar_snapshots_mes(
      "data/paraprobar/datos_com.parquet",
      "data/paraprobar/datos_com_old.parquet",
      "COM"
    ),
    comparar_snapshots_mes(
      "data/paraprobar/datos_levante.parquet",
      "data/paraprobar/datos_levante_old.parquet",
      "Levantes"
    )
  ))
  fwrite(comparacion, file.path(out_dir, "comparacion_snapshots_por_mes.csv"))
}

archivos_clima <- data.table(
  variable = c("temperatura", "precipitacion", "viento"),
  path = file.path(
    "data/raw/inumet/datos_abiertos",
    c(
      "inumet_temperatura_del_aire.csv",
      "inumet_precipitacion_acumulada_horaria.csv",
      "inumet_intensidad_de_viento.csv"
    )
  )
)
clima <- rbindlist(lapply(seq_len(nrow(archivos_clima)), function(i) {
  dt <- fread(
    archivos_clima$path[[i]],
    sep = ";",
    select = c("fecha", "estacion_id"),
    encoding = "UTF-8"
  )[estacion_id == "Aeropuerto Melilla G3"]
  data.table(
    variable = archivos_clima$variable[[i]],
    filas = nrow(dt),
    fecha_min = min(dt$fecha),
    fecha_max = max(dt$fecha),
    cubre_fecha_corte = substr(max(dt$fecha), 1L, 10L) >= as.character(fecha_corte)
  )
}))

fwrite(resumen, file.path(out_dir, "resumen_fuentes.csv"))
fwrite(clima, file.path(out_dir, "resumen_clima.csv"))

cat("\nResumen de fuentes\n")
print(resumen)
cat("\nComparacion con snapshots anteriores\n")
if (comparar_snapshots) print(comparacion) else cat("Omitida en esta corrida.\n")
cat("\nCobertura de clima en Melilla G3\n")
print(clima)
