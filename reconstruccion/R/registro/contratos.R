# Contratos minimos R02. No carga binarios ni aplica algoritmos.

# Valida un texto escalar obligatorio.  Entradas: valor y etiqueta. Salida: TRUE
# invisible o error.

# Valida un texto escalar obligatorio.  Entradas: valor y etiqueta. Salida: TRUE
# invisible o error.
rf_text <- function(x, label) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(x)))
    stop("Texto requerido: ", label)
  invisible(TRUE)
}

# Comprueba la presencia de campos obligatorios.  Entradas: objeto, campos y etiqueta.
# Salida: ninguna o error.

# Comprueba la presencia de campos obligatorios.  Entradas: objeto, campos y etiqueta.
# Salida: ninguna o error.
rf_fields <- function(x, fields, label) {
  missing <- setdiff(fields, names(x))
  if (length(missing))
    stop(label, ": faltan ", paste(missing, collapse = ", "))
}

# Valida identidad, receta y disponibilidad del descriptor de modelo.  Entrada: lista
# de metadatos. Salida: TRUE invisible o error.

# Valida identidad, receta y disponibilidad del descriptor de modelo.  Entrada: lista
# de metadatos. Salida: TRUE invisible o error.
rf_model_contract <- function(x) {
  rf_fields(x, c("contract_version", "model_id", "model_version", "adapter", "target",
    "unit", "cluster_version", "features", "preprocessing_id", "training_reference",
    "availability"), "Modelo")
  if (!identical(x$contract_version, "rf_model_v1"))
    stop("Version de contrato de modelo invalida")
  for (key in c("model_id", "model_version", "adapter", "target", "unit", "cluster_version",
    "preprocessing_id", "training_reference")) rf_text(x[[key]], key)
  if (!x$unit %in% c("cluster_dia", "segmento_dia"))
    stop("Unidad de modelo invalida")
  if (!is.character(x$features) || !length(x$features) || anyNA(x$features) || any(!nzchar(x$features)) ||
    anyDuplicated(x$features))
    stop("Features invalidas o duplicadas")
  rf_fields(x$availability, c("timezone", "com_lag_days", "levante_cutoff"), "Disponibilidad")
  if (!identical(x$availability$timezone, "America/Montevideo") || !identical(as.numeric(x$availability$com_lag_days),
    2) || !identical(x$availability$levante_cutoff, "01:00:00"))
    stop("Disponibilidad incompatible con contrato operativo")
  invisible(TRUE)
}

# Comprueba columnas requeridas y compatibilidad espacial.  Entradas: tabla de features
# y descriptor. Salida: TRUE invisible o error.

# Comprueba columnas requeridas y compatibilidad espacial.  Entradas: tabla de features
# y descriptor. Salida: TRUE invisible o error.
rf_feature_contract <- function(data, model) {
  rf_model_contract(model)
  if (!is.data.frame(data))
    stop("Features debe ser data.frame")
  rf_fields(data, c("version_cluster", model$features), "Features")
  if (anyNA(data$version_cluster) || any(data$version_cluster != model$cluster_version))
    stop("Version espacial incompatible")
  # La receta del adaptador resolvera tipos, orden e imputacion; no reentrenar aqui.
  invisible(TRUE)
}

# Valida claves, scores y ranking del producto cluster/dia.  Entrada: tabla de
# predicciones. Salida: TRUE invisible o error.

# Valida claves, scores y ranking del producto cluster/dia.  Entrada: tabla de
# predicciones. Salida: TRUE invisible o error.
rf_prediction_contract <- function(data) {
  if (!is.data.frame(data) || !nrow(data))
    stop("Predicciones vacias o invalidas")
  keys <- c("cluster_id", "dia_objetivo", "modelo_id", "version_modelo")
  rf_fields(data, c(keys, "version_cluster", "pred_prob", "ranking_dia", "target_app"),
    "Predicciones")
  if (!inherits(data$dia_objetivo, "Date"))
    stop("dia_objetivo debe ser Date")
  for (k in c(keys, "version_cluster", "target_app")) {
    if (anyNA(data[[k]]) || any(!nzchar(as.character(data[[k]]))))
      stop("Clave o identidad vacia: ", k)
  }
  if (anyDuplicated(data[keys]))
    stop("Clave de prediccion duplicada")
  if (!is.numeric(data$pred_prob) || any(!is.finite(data$pred_prob)) || any(data$pred_prob <
    0 | data$pred_prob > 1))
    stop("Score fuera de rango")
  if (!is.numeric(data$ranking_dia) || anyNA(data$ranking_dia) || any(!is.finite(data$ranking_dia) |
    data$ranking_dia < 1 | data$ranking_dia != floor(data$ranking_dia)))
    stop("Ranking invalido")
  invisible(TRUE)
}

# Valida modelos y capas de una publicacion coherente.  Entrada: descriptor de
# publicacion. Salida: TRUE invisible o error.

# Valida modelos y capas de una publicacion coherente.  Entrada: descriptor de
# publicacion. Salida: TRUE invisible o error.
rf_publication_contract <- function(x) {
  rf_fields(x, c("contract_version", "publication_id", "cluster_version", "models", "layers"),
    "Publicacion")
  if (!identical(x$contract_version, "rf_publication_v1"))
    stop("Version de publicacion invalida")
  for (key in c("publication_id", "cluster_version")) rf_text(x[[key]], key)
  if (!is.list(x$models) || !length(x$models))
    stop("Publicacion sin modelos")
  for (model in x$models) {
    rf_model_contract(model)
    if (model$cluster_version != x$cluster_version)
      stop("Publicacion mezcla versiones espaciales")
  }
  ids <- vapply(x$models, function(m) paste(m$model_id, m$model_version, sep = ":"), character(1))
  if (anyDuplicated(ids))
    stop("Modelo repetido en publicacion")
  rf_fields(x$layers, c("operacional", "historico", "referencia"), "Capas")
  for (k in c("operacional", "historico", "referencia")) rf_text(x$layers[[k]], k)
  invisible(TRUE)
}


# Comprueba conteos y consistencia entre barrios y total.  Entradas: serie completa por
# grupo y tolerancia. Salida: TRUE invisible o error.

# Comprueba conteos y consistencia entre barrios y total.  Entradas: serie completa por
# grupo y tolerancia. Salida: TRUE invisible o error.
rf_series_contract <- function(data, tolerance = 1e-06) {
  if (!is.data.frame(data) || !nrow(data))
    stop("Serie vacia o invalida")
  keys <- c("dia_objetivo", "nivel_territorial", "territorio_id", "escenario")
  rf_fields(data, c(keys, "clusters_estimados", "clusters_observados", "clusters_evaluados",
    "estado_observacion"), "Serie")
  if (!inherits(data$dia_objetivo, "Date") || anyNA(data[keys]) || anyDuplicated(data[keys]))
    stop("Claves de serie invalidas")
  if (any(!data$nivel_territorial %in% c("montevideo", "barrio")))
    stop("Nivel territorial invalido")
  for (k in c("clusters_estimados", "clusters_observados", "clusters_evaluados")) {
    if (!is.numeric(data[[k]]) || any(!is.finite(data[[k]])) || any(data[[k]] < 0))
      stop("Conteo invalido: ", k)
  }
  if (any(data$clusters_estimados > data$clusters_evaluados + tolerance) || any(data$clusters_observados >
    data$clusters_evaluados))
    stop("Conteo supera exposicion")
  groups <- split(data, interaction(data$dia_objetivo, data$escenario, drop = TRUE))
  for (g in groups) {
    total <- g[g$nivel_territorial == "montevideo", , drop = FALSE]
    barrios <- g[g$nivel_territorial == "barrio", , drop = FALSE]
    if (nrow(total) != 1L || !nrow(barrios))
      stop("Serie requiere total y barrios")
    for (k in c("clusters_estimados", "clusters_observados", "clusters_evaluados")) {
      if (abs(total[[k]] - sum(barrios[[k]])) > tolerance)
        stop("Total y barrios inconsistentes: ", k)
    }
  }
  invisible(TRUE)
}
