leer_configuracion_impala <- function() {
  nombres <- c(
    jdbc_jar = "IMPALA_JDBC_JAR",
    jdbc_url = "IMPALA_JDBC_URL",
    usuario = "IMPALA_USER",
    password = "IMPALA_PASSWORD"
  )
  valores <- Sys.getenv(unname(nombres), unset = "")
  faltantes <- unname(nombres)[!nzchar(valores)]

  if (length(faltantes)) {
    stop(
      "Falta configurar en el entorno: ",
      paste(faltantes, collapse = ", ")
    )
  }

  stats::setNames(as.list(valores), names(nombres))
}

