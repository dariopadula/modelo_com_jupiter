# Extractor acotado de las tablas originales. No declara cierres por inferencia.
# Requiere entregas.R. La funcion query inyectable permite probar sin conexion.

# Consultas solo a tablas conocidas y meses validados; conserva columnas crudas originales.
rf_impala_sql <- function(family, month, com_columns = NULL) {
  month <- rf_months(month)
  if (length(month) != 1L) stop("Una consulta Impala por mes")
  if (family == "com") {
    columns <- setdiff(com_columns, c("transportista", "direccion", "gid_contenedor"))
    table <- "prod_limpieza.reclamos_com"
  } else if (family == "levante") {
    columns <- c("levante_contenedor_id", "levante_fecha_levante", "levante_circuito",
      "levante_posicion_en_circuito", "levante_activo", "levante_motivo_no_levante_id",
      "levante_motivo_no_levante_descripcion", "levante_fact", "levante_porcentaje_llenado",
      "levante_periodo", "levante_longitud", "levante_latitud", "anio", "anio_mes")
    table <- "prod_limpieza.v_analitica_levante_de_contenedores"
  } else stop("Fuente Impala desconocida")
  if (!length(columns) || anyNA(columns) || any(!grepl("^[a-zA-Z_][a-zA-Z0-9_]*$", columns))) {
    stop("Columnas Impala invalidas")
  }
  paste0("SELECT ", paste(columns, collapse = ", "), " FROM ", table, " WHERE anio_mes = ", month)
}

# Abre una conexion JDBC desde configuracion validada y secretos del entorno.
# El llamador cierra siempre, incluso si falla una consulta.
rf_impala_connect <- function(config) {
  if (!identical(config$values[["RF_EXTRACTOR"]], "impala")) stop("RF_EXTRACTOR debe ser impala")
  if (!requireNamespace("RJDBC", quietly = TRUE) || !requireNamespace("DBI", quietly = TRUE)) {
    stop("Se requieren RJDBC, DBI y Java ya instalados")
  }
  driver <- RJDBC::JDBC("com.cloudera.impala.jdbc.Driver", config$values[["IMPALA_JDBC_JAR"]])
  DBI::dbConnect(driver, config$values[["IMPALA_JDBC_URL"]],
    Sys.getenv("IMPALA_USER"), Sys.getenv("IMPALA_PASSWORD"))
}

# Extrae un pedido explicito a un destino nuevo. Las particiones/contexto y cierres
# pertenecen al productor del pedido; el ultimo evento no se convierte en cierre.
rf_extract_impala <- function(request, output, config, query = NULL, context_days = 90L) {
  if (file.exists(output)) stop("El destino de extraccion ya existe")
  for (family in c("com", "levante")) {
    months <- rf_months(request[[family]]$partitions_replaced)
    needed <- if (family == "levante") rf_context_months(months, context_days) else months
    if (length(needed) > 6L) stop("Extraccion acotada a seis meses por fuente; dividir el pedido")
    if (is.null(request[[family]]$complete_through) ||
        is.na(as.Date(request[[family]]$complete_through)) ||
        is.null(request[[family]]$available_through_timestamp)) {
      stop("Falta cierre/disponibilidad del productor")
    }
    rf_delivery_time(request[[family]]$available_through_timestamp)
  }
  rf_version_id(request$delivery_id)
  if (is.null(query)) {
    connection <- rf_impala_connect(config)
    on.exit(DBI::dbDisconnect(connection), add = TRUE)
    query <- function(sql) DBI::dbGetQuery(connection, sql)
  }
  columns <- query("DESCRIBE prod_limpieza.reclamos_com")$name
  manifest <- list(contract_version = "fuentes_v2", schema_version = "crudo_original_v1",
    delivery_id = request$delivery_id, timezone = "America/Montevideo", status = "lista",
    extract_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z", tz = "America/Montevideo"))
  dir.create(output, recursive = TRUE)
  for (family in c("com", "levante")) {
    item <- request[[family]]
    targets <- rf_months(item$partitions_replaced)
    months <- if (family == "levante") rf_context_months(targets, context_days) else targets
    if (length(months) > 6L) stop("Extraccion acotada a seis meses por fuente; dividir el pedido")
    counts <- list()
    objects <- list()
    timestamps <- character()
    for (month in months) {
      data <- as.data.frame(query(rf_impala_sql(family, month, columns)))
      if (length(setdiff(rf_raw_columns(family), names(data))) || anyNA(data$anio_mes) ||
          any(as.character(data$anio_mes) != month)) stop("Impala devolvio otra particion")
      event_column <- if (family == "com") "fecha_de_reclamo" else "levante_fecha_levante"
      if (!event_column %in% names(data)) stop("Falta fecha cruda original")
      timestamps <- c(timestamps, as.character(data[[event_column]]))
      key <- paste0(family, "/", month, ".parquet")
      dir.create(file.path(output, family), showWarnings = FALSE)
      arrow::write_parquet(data, file.path(output, key))
      counts[[month]] <- nrow(data)
      objects[[length(objects) + 1L]] <- list(key = key, partitions = month, row_count = nrow(data),
        md5 = unname(tools::md5sum(file.path(output, key))))
    }
    timestamps <- timestamps[!is.na(timestamps) & nzchar(timestamps)]
    item$partitions_replaced <- targets
    item$row_count_by_partition <- counts[targets]
    item$replacement_scope_by_partition <- as.list(stats::setNames(rep("complete", length(targets)), targets))
    item$objects <- objects
    item["min_event_timestamp"] <- list(if (length(timestamps)) min(timestamps) else NULL)
    item["max_event_timestamp"] <- list(if (length(timestamps)) max(timestamps) else NULL)
    manifest[[family]] <- item
  }
  rf_validate_delivery(manifest, context_days)
  rf_write_json(manifest, file.path(output, "manifest.json"))
  invisible(manifest)
}
