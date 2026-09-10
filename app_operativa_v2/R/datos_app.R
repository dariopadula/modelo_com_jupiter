leer_dataset_app <- function(path, requerido = TRUE) {
  if (!dir.exists(path)) {
    if (requerido) {
      stop("No existe el dataset: ", path)
    }
    return(data.table::data.table())
  }

  data.table::as.data.table(
    as.data.frame(arrow::open_dataset(path, format = "parquet"))
  )
}

primer_path_existente <- function(candidatos, archivo = FALSE) {
  candidatos <- candidatos[nzchar(candidatos)]
  existe <- if (archivo) file.exists(candidatos) else dir.exists(candidatos)
  encontrados <- candidatos[existe]
  if (!length(encontrados)) return(NA_character_)
  normalizePath(encontrados[[1]], winslash = "/", mustWork = TRUE)
}

resolver_path_datos_app <- function() {
  configurado <- Sys.getenv("APP_DATA_PATH", unset = "")
  candidatos <- c(
    configurado,
    "data/operacional"
  )
  candidatos <- candidatos[nzchar(candidatos)]
  existentes <- candidatos[dir.exists(candidatos)]

  if (length(existentes) == 0L) {
    stop("No se encontro una salida operativa para la app")
  }
  normalizePath(existentes[[1]], winslash = "/", mustWork = TRUE)
}

seleccionar_top_n <- function(dt, n) {
  n <- max(0L, min(as.integer(round(n)), nrow(dt)))
  if (n == 0L) return(dt[0])
  dt[order(-pred_prob, ranking_dia)][seq_len(n)]
}

seleccionar_por_barrio <- function(dt, modo, valor = NULL, cupos = NULL) {
  if (!nrow(dt)) return(dt)
  if (!is.null(cupos)) {
    cupos <- data.table::as.data.table(cupos)
    resultado <- dt[cupos, on = "barrio", allow.cartesian = TRUE][
      order(barrio, -pred_prob)
    ][, head(.SD, max(0L, as.integer(round(cupo[[1]])))), by = barrio]
    resultado[, cupo := NULL]
    return(resultado)
  }
  if (modo == "porcentaje_barrio") {
    pct <- as.numeric(valor) / 100
    return(dt[order(barrio, -pred_prob)][
      , head(.SD, max(1L, ceiling(.N * pct))), by = barrio
    ])
  }
  if (modo == "fijo_barrio") {
    return(dt[order(barrio, -pred_prob)][
      , head(.SD, max(0L, as.integer(valor))), by = barrio
    ])
  }
  dt
}

formatear_hora <- function(x) {
  if (length(x) == 0L || all(is.na(x))) return("Sin dato")
  format(max(x, na.rm = TRUE), "%d/%m/%Y %H:%M")
}
