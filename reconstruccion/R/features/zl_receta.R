# Deriva las variables operativas y territoriales del bundle ZL seleccionado.
# Entradas: features COM, referencia de segmentos y calendario de feriados.
# Salida: tabla cluster/dia con las 36 variables numericas del escenario efectivo.
rf_prepare_zl_features <- function(features, cluster_segment, holidays, feature_names) {
  required_features <- c("cluster_id", "dia", "anio_mes", "version_cluster",
    "min_tiempo_desde_ultimo_levante_pred", "mean_tiempo_desde_ultimo_levante_pred",
    "max_tiempo_desde_ultimo_levante_pred", "min_levante_periodo", "mean_levante_periodo",
    "max_levante_periodo", "mean_dias_total_tramo_inferido_estado", "max_dias_total_tramo_inferido_estado")
  missing_features <- setdiff(required_features, names(features))
  if (length(missing_features)) {
    stop("Faltan columnas COM para preparar ZL: ", paste(missing_features, collapse = ", "))
  }
  required_segment <- c("version_cluster", "cluster_id", "porc_nbi_segmento",
    "porc_asentamiento_nbi_segmento", "porc_vivienda_inadecuada_segmento", "densidad_pob_km2",
    "cluster_multisegmento", "pct_posiciones_segmento_principal")
  missing_segment <- setdiff(required_segment, names(cluster_segment))
  if (length(missing_segment)) {
    stop("Faltan columnas territoriales ZL: ", paste(missing_segment, collapse = ", "))
  }

  daily <- data.table::copy(data.table::as.data.table(features))
  segments <- data.table::copy(data.table::as.data.table(cluster_segment))
  daily[, `:=`(cluster_id = as.character(cluster_id), version_cluster = as.character(version_cluster),
    dia = data.table::as.IDate(dia))]
  segments[, `:=`(cluster_id = as.character(cluster_id), version_cluster = as.character(version_cluster))]
  if (anyDuplicated(daily[, .(version_cluster, cluster_id, dia)])) {
    stop("Features COM duplicadas por version, cluster y dia")
  }
  if (anyDuplicated(segments[, .(version_cluster, cluster_id)])) {
    stop("Referencia de segmento duplicada por version y cluster")
  }

  segment_fields <- required_segment[-c(1L, 2L)]
  result <- merge(daily, segments[, c("version_cluster", "cluster_id", segment_fields), with = FALSE],
    by = c("version_cluster", "cluster_id"), all.x = TRUE, sort = FALSE)
  result[, `:=`(
    exceso_min_tiempo_periodo_pred_pos = pmax(min_tiempo_desde_ultimo_levante_pred - min_levante_periodo, 0),
    exceso_mean_tiempo_periodo_pred_pos = pmax(mean_tiempo_desde_ultimo_levante_pred - mean_levante_periodo, 0),
    exceso_max_tiempo_periodo_pred_pos = pmax(max_tiempo_desde_ultimo_levante_pred - max_levante_periodo, 0)
  )]
  result[, `:=`(
    exceso_min_tiempo_periodo_pred_trunc7 = pmin(exceso_min_tiempo_periodo_pred_pos, 7),
    exceso_mean_tiempo_periodo_pred_trunc7 = pmin(exceso_mean_tiempo_periodo_pred_pos, 7),
    exceso_max_tiempo_periodo_pred_trunc7 = pmin(exceso_max_tiempo_periodo_pred_pos, 7)
  )]

  holiday_days <- data.table::as.IDate(holidays)
  result[, dia_semana := as.integer(format(dia, "%u"))]
  result[, fin_de_semana := dia_semana %in% c(6L, 7L)]
  result[, es_feriado := dia %in% holiday_days]
  result[, vispera_feriado := (dia + 1L) %in% holiday_days]
  result[, dia_habil := !fin_de_semana & !es_feriado]

  missing_model_features <- setdiff(feature_names, names(result))
  if (length(missing_model_features)) {
    stop("No se pudieron construir features del bundle ZL: ", paste(missing_model_features, collapse = ", "))
  }
  result[]
}

# Une el target observado ZL al universo de features y conserva solo visitas efectivas.
# Entradas: features completas y comparacion COM/ZL; salida: filas etiquetadas del modelo.
rf_prepare_zl_training_data <- function(features, comparison, feature_names, selected_months) {
  required_comparison <- c("version_cluster", "cluster_id", "dia", "anio_mes", "hay_zl_visita_efectiva",
    "hay_zl_voluminosos", "hay_zl_problema_comparable")
  missing_comparison <- setdiff(required_comparison, names(comparison))
  if (length(missing_comparison)) {
    stop("Faltan columnas de comparacion ZL: ", paste(missing_comparison, collapse = ", "))
  }
  eligible <- data.table::copy(data.table::as.data.table(comparison))
  eligible <- eligible[hay_zl_visita_efectiva == TRUE & hay_zl_voluminosos != TRUE &
    anio_mes %in% selected_months]
  eligible[, target_problema_observado := as.integer(hay_zl_problema_comparable == TRUE)]
  eligible[, `:=`(cluster_id = as.character(cluster_id), version_cluster = as.character(version_cluster),
    dia = data.table::as.IDate(dia))]
  if (anyDuplicated(eligible[, .(version_cluster, cluster_id, dia)])) {
    stop("Target ZL duplicado por version, cluster y dia")
  }

  daily <- data.table::copy(data.table::as.data.table(features))
  daily[, `:=`(cluster_id = as.character(cluster_id), version_cluster = as.character(version_cluster),
    dia = data.table::as.IDate(dia))]
  keys <- c("version_cluster", "cluster_id", "dia")
  # El legado conserva el orden de las features al unir las etiquetas.
  # Ese orden determina la primera aparicion de dias en el split aleatorio ZL.
  join_keys <- c(keys, "anio_mes")
  training <- eligible[, c(join_keys, "target_problema_observado"), with = FALSE][
    daily, on = join_keys, nomatch = 0]
  absent_features <- setdiff(feature_names, names(training))
  if (length(absent_features)) {
    stop("Faltan features ZL para entrenamiento: ", paste(absent_features, collapse = ", "))
  }
  training[!is.na(target_problema_observado)][]
}

# Imputa variables numericas y codifica categorias con la receta congelada del bundle.
# Entradas: datos, nombres y preparacion opcional; salida: matriz XGBoost y receta.
rf_prepare_zl_matrix <- function(data, numeric_features, categorical_features = character(), prep = NULL) {
  required <- c(numeric_features, categorical_features)
  missing <- setdiff(required, names(data))
  if (length(missing)) {
    stop("Faltan variables para matriz ZL: ", paste(missing, collapse = ", "))
  }
  numeric_data <- data.table::copy(data.table::as.data.table(data)[, ..numeric_features])
  for (column in names(numeric_data)) {
    if (is.logical(numeric_data[[column]])) {
      numeric_data[, (column) := as.integer(get(column))]
    }
    if (is.integer(numeric_data[[column]])) {
      numeric_data[, (column) := as.numeric(get(column))]
    }
  }

  if (is.null(prep)) {
    medians <- lapply(numeric_features, function(column) {
      median_value <- stats::median(numeric_data[[column]], na.rm = TRUE)
      if (is.na(median_value) || is.infinite(median_value)) {
        median_value <- 0
      }
      median_value
    })
    names(medians) <- numeric_features
    levels <- setNames(lapply(categorical_features, function(column) {
      sort(unique(c(rf_normalize_zl_level(data[[column]]), "OTRO", "SIN_DATO")))
    }), categorical_features)
    prep <- list(medianas = medians, niveles = levels)
  }
  if (!identical(names(prep$medianas), numeric_features) && !setequal(names(prep$medianas), numeric_features)) {
    stop("Orden o contenido de medianas incompatible con el bundle ZL")
  }
  numeric_matrix <- as.matrix(numeric_data[, ..numeric_features])
  for (column_index in seq_along(numeric_features)) {
    column <- numeric_features[[column_index]]
    missing_values <- is.na(numeric_matrix[, column_index]) | is.infinite(numeric_matrix[, column_index])
    numeric_matrix[missing_values, column_index] <- prep$medianas[[column]]
  }
  colnames(numeric_matrix) <- numeric_features

  matrices <- list(numeric_matrix)
  for (column in categorical_features) {
    levels <- prep$niveles[[column]]
    values <- rf_normalize_zl_level(data[[column]])
    values[!values %in% levels] <- "OTRO"
    dummy <- stats::model.matrix(~ factor(values, levels = levels) - 1L)
    colnames(dummy) <- paste0(column, "__", make.names(levels, unique = TRUE))
    matrices[[length(matrices) + 1L]] <- dummy
  }
  matrix <- do.call(cbind, matrices)
  storage.mode(matrix) <- "numeric"
  list(x = matrix, prep = prep)
}

# Normaliza categorías con la misma regla usada al entrenar el bundle efectivo.
rf_normalize_zl_level <- function(value) {
  value <- toupper(trimws(as.character(value)))
  value[is.na(value) | value == ""] <- "SIN_DATO"
  iconv(value, from = "", to = "ASCII//TRANSLIT")
}
