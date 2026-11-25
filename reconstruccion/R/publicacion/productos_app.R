# Construye productos locales propios con scores ya calculados; nunca entrena ni predice.
# La activacion recuperable local/S3 se implementa en R09. Una salida parcial no es legible.

rf_app_detail_columns <- function() {
  c("cluster_id", "dia_objetivo", "modelo_id", "version_modelo", "version_cluster", "pred_prob",
    "ranking_dia", "percentil_riesgo", "estado_prediccion", "estado_periodo_app", "estado_observacion",
    "tuvo_reclamo_observado", "n_reclamos_observado", "hay_zl_visita_efectiva", "problema_zl_observado",
    "n_zl_problema_comparable", "estado_observacion_zl", "timestamp_ejecucion")
}

# Verifica claves, rankings, cobertura y targets por fecha, conservando NA sin visita ZL.
rf_validate_app_day <- function(predictions, master) {
  # Los indices heredados de Arrow pueden quedar obsoletos. Validar los valores,
  # sin modificar la tabla del llamador ni confiar en sus indices de busqueda.
  predictions <- copy(predictions)
  setindexv(predictions, NULL)
  setkeyv(predictions, NULL)
  required <- c(rf_app_detail_columns(), "n_contenedores_activos")
  if (length(setdiff(required, names(predictions))) || !nrow(predictions)) {
    stop("Faltan columnas o filas del producto COM/ZL")
  }
  if (anyNA(predictions[, .(cluster_id, dia_objetivo, modelo_id, version_modelo, version_cluster)]) ||
      anyDuplicated(predictions[, .(cluster_id, dia_objetivo, modelo_id, version_modelo)]) ||
      uniqueN(predictions$dia_objetivo) != 1L || uniqueN(predictions$version_cluster) != 1L ||
      !setequal(unique(predictions$modelo_id), c("com_reclamo", "zl_problema")) ||
      any(!is.finite(predictions$pred_prob) | predictions$pred_prob < 0 | predictions$pred_prob > 1)) {
    stop("Claves, modelos o scores incompatibles con la publicacion")
  }
  if (any(!predictions$cluster_id %in% master$cluster_id) ||
      any(predictions$version_cluster != unique(master$version_cluster))) {
    stop("El maestro no cubre la version y todos los clusters predichos")
  }
  for (family in c("com_reclamo", "zl_problema")) {
    data <- predictions[modelo_id == family][order(ranking_dia)]
    if (uniqueN(data$version_modelo) != 1L || anyDuplicated(data$cluster_id) ||
        !identical(as.integer(data$ranking_dia), seq_len(nrow(data))) ||
        any(diff(data$pred_prob) > 1e-12) ||
        anyNA(data$percentil_riesgo) || max(abs(data$percentil_riesgo - data$ranking_dia / nrow(data))) > 1e-10) {
      stop("Version, ranking o percentiles invalidos en ", family)
    }
    # Conserva el ranking publicado. Reordenar floats casi iguales puede cambiar
    # posiciones entre plataformas; los empates exactos mantienen la clave estable.
    ties <- which(diff(data$pred_prob) == 0)
    if (length(ties) && any(data$cluster_id[ties] > data$cluster_id[ties + 1L])) {
      stop("Empates exactos sin orden estable por cluster_id")
    }
  }
  visited <- predictions[modelo_id == "zl_problema" & hay_zl_visita_efectiva == 1L]
  not_visited <- predictions[modelo_id == "zl_problema" & hay_zl_visita_efectiva != 1L]
  if (anyNA(visited$problema_zl_observado) || !all(visited$problema_zl_observado %in% c(0, 1)) ||
      any(!is.na(not_visited$problema_zl_observado))) {
    stop("Targets ZL incompatibles: sin visita no equivale a sin problema")
  }
  closed <- predictions[modelo_id == "com_reclamo" & estado_periodo_app == "historico_cerrado"]
  if (anyNA(closed$tuvo_reclamo_observado) || any(closed$estado_observacion != "cerrado")) {
    stop("Un periodo COM declarado cerrado no tiene observados completos")
  }
  invisible(TRUE)
}

# Recibe rutas propias a scores particionados, series/maestro y referencia territorial.
# Escribe en un destino nuevo; el manifiesto ready se crea solo tras validar todos los dias.
rf_build_app_products <- function(package, output) {
  if (file.exists(output) || dir.exists(output)) {
    stop("El destino ya existe; elegir una publicacion nueva")
  }
  master <- copy(as.data.table(package$master))
  series <- copy(as.data.table(package$series))
  required_master <- c("version_cluster", "cluster_id", "barrio", "cod_barrio_ine", "x", "y")
  required_series <- c("dia_objetivo", "nivel_territorial", "territorio_id", "territorio_nombre",
    "clusters_estimados", "clusters_observados", "clusters_evaluados", "escenario", "split_modelo", "estado_observacion")
  if (length(setdiff(required_master, names(master))) || length(setdiff(required_series, names(series))) ||
      !nrow(master) || anyDuplicated(master$cluster_id) || uniqueN(master$version_cluster) != 1L ||
      any(!is.finite(master$x) | !is.finite(master$y)) || !file.exists(package$shape_path)) {
    stop("Maestro, serie o referencia territorial incompletos")
  }
  series[, dia_objetivo := as.Date(dia_objetivo)]
  if (!nrow(series) || !identical(unique(series$escenario), "P3_compacto") ||
      anyDuplicated(series[, .(dia_objetivo, nivel_territorial, territorio_id, escenario)])) {
    stop("La serie agregada no corresponde al contrato P3")
  }
  city <- series[nivel_territorial == "montevideo"]
  neighborhoods <- series[nivel_territorial == "barrio", .(prediction = sum(clusters_estimados),
    observed = sum(clusters_observados), exposure = sum(clusters_evaluados)), by = dia_objetivo]
  control <- merge(city, neighborhoods, by = "dia_objetivo", all = TRUE)
  if (anyNA(control$prediction) || anyNA(control$clusters_estimados) ||
      any(abs(control$clusters_estimados - control$prediction) > 1e-6) ||
      any(control$clusters_observados != control$observed, na.rm = TRUE) ||
      any(control$clusters_evaluados != control$exposure)) {
    stop("La serie barrial no suma a Montevideo")
  }
  dataset <- arrow::open_dataset(package$scores_path,
    partitioning = arrow::hive_partition(dia_objetivo = arrow::date32(), modelo_id = arrow::utf8()))
  days <- sort(as.Date(dplyr::collect(dplyr::distinct(dataset, dia_objetivo))$dia_objetivo))
  if (!length(days) || anyNA(days) || !max(days) %in% city$dia_objetivo) {
    stop("Falta la serie agregada del dia operativo")
  }
  dir.create(output, recursive = TRUE)
  rows <- 0
  for (day_text in as.character(days)) {
    day <- as.Date(day_text)
    predictions <- as.data.table(as.data.frame(
      dplyr::collect(dplyr::filter(dataset, dia_objetivo == !!day))
    ))
    rf_validate_app_day(predictions, master)
    rows <- rows + nrow(predictions)
    columns <- rf_app_detail_columns()
    arrow::write_dataset(predictions[, ..columns], file.path(output, "historico/detalle_cluster_dia"),
      format = "parquet", partitioning = c("dia_objetivo", "modelo_id"),
      existing_data_behavior = "overwrite", compression = "zstd")
    if (day == max(days)) {
      arrow::write_dataset(predictions, file.path(output, "operacional/predicciones_operativas_cluster_dia"),
        format = "parquet", partitioning = "modelo_id", compression = "zstd")
    }
  }
  arrow::write_dataset(series, file.path(output, "historico/serie_historica_com"), format = "parquet", compression = "zstd")
  arrow::write_dataset(master, file.path(output, "referencia/maestro_clusters"), format = "parquet", compression = "zstd")
  if (!file.copy(package$shape_path, file.path(output, "referencia/barrios_mvd_23_pg.gpkg"), overwrite = FALSE)) {
    stop("No se pudo copiar la referencia de barrios")
  }
  manifest <- list(publication_id = basename(normalizePath(output, winslash = "/")), status = "ready",
    operational_day = as.character(max(days)), dates = as.character(days), detail_rows = rows,
    cluster_version = unique(master$version_cluster), days_validation = package$days_validation,
    provenance = package$provenance, label = package$label)
  saveRDS(manifest, file.path(output, "publicacion.rds"))
  manifest
}
