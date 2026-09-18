validar_contrato_splits <- function(contrato,
                                     splits_esperados = c(
                                       "contexto", "entrenamiento",
                                       "validacion", "test"
                                     )) {
  contrato <- data.table::as.data.table(data.table::copy(contrato))
  columnas <- c(
    "version_split", "orden", "split", "fecha_desde", "fecha_hasta",
    "uso_permitido", "puede_ajustar", "puede_seleccionar",
    "puede_reportar_metricas_ahora", "estado"
  )
  faltantes <- setdiff(columnas, names(contrato))
  if (length(faltantes)) {
    stop("Faltan columnas en el contrato de splits: ",
      paste(faltantes, collapse = ", "))
  }

  contrato[, `:=`(
    fecha_desde = data.table::as.IDate(fecha_desde),
    fecha_hasta = data.table::as.IDate(fecha_hasta)
  )]
  data.table::setorder(contrato, orden)

  if (data.table::uniqueN(contrato$version_split) != 1L) {
    stop("El contrato debe contener una unica version_split")
  }
  if (!identical(contrato$orden, seq_len(nrow(contrato)))) {
    stop("El orden de los splits no es consecutivo")
  }
  if (!identical(contrato$split, splits_esperados)) {
    stop("Los splits no coinciden con el orden esperado")
  }
  if (any(contrato$fecha_desde > contrato$fecha_hasta)) {
    stop("Hay intervalos con fecha_desde posterior a fecha_hasta")
  }
  if (nrow(contrato) > 1L) {
    inicio_esperado <- contrato$fecha_hasta[-nrow(contrato)] + 1L
    if (!identical(contrato$fecha_desde[-1L], inicio_esperado)) {
      stop("Los intervalos tienen huecos o superposiciones")
    }
  }

  test <- contrato[split == "test"]
  if (nrow(test) != 1L || test$estado != "sellado" ||
      test$puede_reportar_metricas_ahora || test$puede_seleccionar ||
      test$puede_ajustar) {
    stop("El test debe permanecer sellado y fuera de ajuste, seleccion y metricas")
  }

  contrato[]
}

leer_contrato_splits <- function(
    path = "config/splits_reevaluacion_2026.csv") {
  if (!file.exists(path)) stop("No existe el contrato de splits: ", path)
  validar_contrato_splits(data.table::fread(path))
}

asignar_split_congelado <- function(datos,
                                    fecha_col = "dia",
                                    contrato = leer_contrato_splits(),
                                    exigir_cobertura = TRUE) {
  datos <- data.table::as.data.table(data.table::copy(datos))
  if (!fecha_col %in% names(datos)) {
    stop("No existe la columna de fecha: ", fecha_col)
  }
  fechas <- data.table::as.IDate(datos[[fecha_col]])
  datos[, `:=`(
    version_split = contrato$version_split[[1L]],
    split = NA_character_
  )]

  for (ii in seq_len(nrow(contrato))) {
    idx <- fechas >= contrato$fecha_desde[[ii]] &
      fechas <= contrato$fecha_hasta[[ii]]
    datos[idx, split := contrato$split[[ii]]]
  }

  if (exigir_cobertura && datos[is.na(split), .N] > 0L) {
    rango <- range(fechas[is.na(datos$split)])
    stop("Hay fechas fuera del contrato: ",
      paste(as.character(rango), collapse = " a "))
  }
  datos[]
}
