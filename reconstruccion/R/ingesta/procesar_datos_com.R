# Valida marcas declaradas sin inferir cierre a partir del ultimo evento.  Entrada:
# lista de marcas de fuente. Salida: TRUE invisible o error.
rf_source_marks <- function(marks) {
  required <- c("source_id", "timezone", "complete_through", "available_through_timestamp")
  if (!is.list(marks) || !all(required %in% names(marks))) {
    stop("Faltan marcas explicitas de la fuente")
  }
  if (!identical(marks$timezone, "America/Montevideo")) {
    stop("Zona horaria de fuente incompatible")
  }
  if (!is.character(marks$source_id) || length(marks$source_id) != 1L || !nzchar(marks$source_id)) {
    stop("Fuente sin identificador")
  }
  closed <- marks$complete_through
  if (!is.null(closed) && (!inherits(closed, "Date") || length(closed) != 1L || is.na(closed))) {
    stop("Cierre debe ser Date o NULL cuando no esta declarado")
  }
  available <- marks$available_through_timestamp
  if (!is.null(available) && (!inherits(available, "POSIXct") || length(available) != 1L ||
    is.na(available))) {
    stop("Disponibilidad debe ser POSIXct o NULL")
  }
  invisible(TRUE)
}

# Construye asignaciones, base y features desde tablas historicas preparadas.  Entrada:
# fuentes y mapa propios en memoria. Salida: derivados y marcas sin inferir frescura.
rf_process_prepared_com <- function(inputs) {
  required <- c("levante", "com", "position_map", "marks", "from", "through", "target_clusters")
  if (!all(required %in% names(inputs)))
    stop("Insumos COM incompletos")
  rf_source_marks(inputs$marks)
  if (!inherits(inputs$from, "Date") || !inherits(inputs$through, "Date") || length(inputs$from) !=
    1L || length(inputs$through) != 1L || anyNA(c(inputs$from, inputs$through)) || inputs$from >
    inputs$through) {
    stop("Rango de procesamiento invalido")
  }
  levante <- data.table::copy(data.table::as.data.table(inputs$levante))
  com <- data.table::copy(data.table::as.data.table(inputs$com))
  map <- data.table::copy(data.table::as.data.table(inputs$position_map))
  versions <- unique(map$version_cluster)
  if (length(versions) != 1L || anyNA(versions))
    stop("Mapa debe tener una sola version espacial")
  levante <- levante[dia >= inputs$from & dia <= inputs$through]
  com <- com[dia >= inputs$from & dia <= inputs$through]
  if (!nrow(levante))
    stop("No hay levantes en el rango")
  assignments <- asignar_com_a_contenedores_activos(com, levante, map)$asignaciones_com
  # El rango viene del insumo declarado, no del primer/ultimo reclamo: conserva dias
  # sin eventos.
  base <- construir_base_cluster_dia(levante, assignments, map, limitar_rango_fechas_com = FALSE)$base_cluster_dia
  base <- base[cluster_id %in% inputs$target_clusters]
  if (!nrow(base))
    stop("Sin clusters objetivo en la base")
  features <- construir_features_historicas_cluster_dia(base)$features_cluster_dia
  # Diferenciar cero cerrado de un dia cuyo cierre no esta declarado.
  controls <- data.table::data.table(dia = seq(inputs$from, inputs$through, by = "day"))
  counts <- com[, .(eventos_del_bloque = .N), by = dia]
  controls <- counts[controls, on = "dia"]
  controls[is.na(eventos_del_bloque), eventos_del_bloque := 0L]
  controls[, estado_fuente := "no_cerrado"]
  if (!is.null(inputs$marks$complete_through)) {
    controls[dia <= inputs$marks$complete_through, estado_fuente := ifelse(eventos_del_bloque ==
      0L, "sin_eventos", "cerrado_con_eventos")]
  }
  list(assignments = assignments, base = base, features = features, marks = inputs$marks,
    controls = controls, version_cluster = versions[[1L]], cutoff_policy = "historico_preparado_corte_heredado_no_recalculado",
    closure_status = if (is.null(inputs$marks$complete_through)) "no_declarado" else "declarado")
}

# Prepara fuentes crudas con corte local corregido y asignacion espacial propia.
# Entrada: eventos COM/levante, referencia fija, rango y marcas. Salida: derivados COM.
rf_process_raw_com <- function(inputs) {
  required <- c("raw_com", "raw_levante", "cluster_members_ref", "marks", "from", "through",
    "target_clusters")
  if (!all(required %in% names(inputs)))
    stop("Insumos crudos incompletos")
  rf_source_marks(inputs$marks)
  old_timezone <- Sys.getenv("TZ", unset = NA_character_)
  Sys.setenv(TZ = "America/Montevideo")
  on.exit({
    if (is.na(old_timezone)) Sys.unsetenv("TZ") else Sys.setenv(TZ = old_timezone)
  }, add = TRUE)
  levante <- preparar_datos_levante(data.table::copy(inputs$raw_levante), fecha_min = inputs$from,
    fecha_max = inputs$through)
  com <- preparar_datos_com(data.table::copy(inputs$raw_com))
  map <- asignar_posiciones_levante_a_clusters(levante, data.table::copy(inputs$cluster_members_ref))$contenedor_posicion_cluster_actual
  prepared <- list(levante = levante, com = com, position_map = map, marks = inputs$marks,
    from = inputs$from, through = inputs$through, target_clusters = inputs$target_clusters)
  result <- rf_process_prepared_com(prepared)
  result$cutoff_policy <- "01:00_America/Montevideo_R04"
  result
}
