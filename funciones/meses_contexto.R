meses_previos_anio_mes <- function(anio_mes, n = 1) {
  if (length(anio_mes) == 0 || n <= 0) return(integer())

  fechas <- as.Date(paste0(substr(anio_mes, 1, 4), "-", substr(anio_mes, 5, 6), "-01"))

  fechas_previas <- unlist(lapply(fechas, function(fecha) {
    seq.Date(fecha, by = "-1 month", length.out = n + 1)[-1]
  }))

  sort(unique(as.integer(format(as.Date(fechas_previas, origin = "1970-01-01"), "%Y%m"))))
}

meses_lectura_con_contexto <- function(anio_mes_objetivo, meses_contexto_previos = 1) {
  sort(unique(c(
    meses_previos_anio_mes(anio_mes_objetivo, meses_contexto_previos),
    anio_mes_objetivo
  )))
}
