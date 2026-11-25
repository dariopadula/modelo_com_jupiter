# Procesa días COM pendientes con frescura declarada y scores congelados.
# Entradas: features históricas, bundle fijo, marcas de fuentes y ejecución previa.
# Salida: scores, estado, observados actualizados y controles diarios.
rf_run_com_incremental <- function(features, model, state, predictions = NULL, marks,
                                   through_day, universe_n = NULL) {
  required_marks <- c("levante_available_through", "com_complete_through", "timezone", "cutoff_policy")
  if (!is.list(marks) || !all(required_marks %in% names(marks))) {
    stop("Faltan marcas de frescura declaradas")
  }
  if (!identical(marks$timezone, "America/Montevideo")) {
    stop("Zona horaria de marcas incompatible")
  }
  if (!identical(marks$cutoff_policy, "01:00_America/Montevideo_R04")) {
    stop("La politica de corte no corresponde a R04; scoring detenido")
  }
  if (!inherits(marks$levante_available_through, "POSIXct") || length(marks$levante_available_through) != 1L ||
      is.na(marks$levante_available_through)) {
    stop("Disponibilidad de levantes no declarada")
  }
  if (!inherits(marks$com_complete_through, "Date") || length(marks$com_complete_through) != 1L ||
      is.na(marks$com_complete_through)) {
    stop("Cierre COM no declarado; scoring detenido")
  }

  daily <- data.table::copy(data.table::as.data.table(features))
  required_features <- c("cluster_id", "dia", "n_reclamos", "tuvo_reclamo", "n_contenedores_activos", "version_cluster")
  missing_features <- setdiff(required_features, names(daily))
  if (length(missing_features)) {
    stop("Faltan features COM: ", paste(missing_features, collapse = ", "))
  }
  daily[, dia := data.table::as.IDate(dia)]
  if (anyDuplicated(daily[, .(cluster_id, dia)])) {
    stop("Features COM duplicadas por cluster y dia")
  }
  if (any(daily$version_cluster != model$version_cluster)) {
    stop("Version espacial incompatible con el modelo")
  }

  required_state <- c("cluster_id", "fecha_estado", "fecha_reclamos_cerrada_hasta")
  missing_state <- setdiff(required_state, names(state))
  if (length(missing_state)) {
    stop("Estado inicial COM incompleto: ", paste(missing_state, collapse = ", "))
  }
  state <- data.table::copy(data.table::as.data.table(state))
  state_days <- unique(data.table::as.IDate(state$fecha_estado))
  state_closed_days <- unique(data.table::as.IDate(state$fecha_reclamos_cerrada_hasta))
  if (length(state_days) != 1L || is.na(state_days) || length(state_closed_days) != 1L || is.na(state_closed_days) ||
      state_closed_days > state_days || anyDuplicated(state$cluster_id)) stop("Estado inicial COM inconsistente")
  if (any(!(state$cluster_id %in% unique(daily$cluster_id)))) {
    stop("El estado contiene clusters ausentes de las features")
  }
  if (data.table::as.IDate(marks$com_complete_through) < state_closed_days) {
    stop("El cierre COM declarado retrocede respecto del estado persistido")
  }

  start_day <- state_days[[1L]]
  end_day <- data.table::as.IDate(through_day)
  if (length(start_day) != 1L || is.na(start_day) || length(end_day) != 1L || is.na(end_day) || end_day < start_day) {
    stop("Rango incremental COM invalido")
  }

  prior <- if (is.null(predictions)) {
    data.table::data.table()
  } else {
    data.table::copy(data.table::as.data.table(predictions))
  }
  if (nrow(prior)) {
    required_predictions <- c("dia_objetivo", "cluster_id", "pred_prob", "ranking_dia")
    if (length(setdiff(required_predictions, names(prior)))) {
      stop("Predicciones previas incompletas")
    }
    prior[, dia_objetivo := as.Date(dia_objetivo)]
    if (anyDuplicated(prior[, .(dia_objetivo, cluster_id)])) {
      stop("Predicciones previas duplicadas")
    }
  }
  score_columns <- intersect(c("pred_prob", "ranking_dia", "percentil_riesgo", "top_1", "top_5", "top_10", "top_20"), names(prior))
  frozen_before <- if (length(score_columns)) {
    data.table::copy(prior[, c("dia_objetivo", "cluster_id", score_columns), with = FALSE])
  } else {
    NULL
  }

  target_days <- if (end_day > start_day) {
    seq(start_day + 1L, end_day, by = "day")
  } else {
    as.Date(character())
  }
  new_predictions <- list()
  controls <- vector("list", length(target_days))
  safe_through <- start_day
  blocked <- FALSE
  for (index in seq_along(target_days)) {
    target_day <- target_days[[index]]
    if (blocked) {
      controls[[index]] <- data.table::data.table(
        dia_objetivo = as.Date(target_day), estado_prediccion = "no_generada",
        motivo = "dia_anterior_bloqueado", fecha_reclamos_requerida = as.Date(target_day - 2L)
      )
      next
    }
    existing <- nrow(prior) && any(prior$dia_objetivo == as.Date(target_day))
    required_levante <- as.POSIXct(paste(as.Date(target_day), "01:00:00"), tz = "America/Montevideo")
    required_com_day <- target_day - 2L
    fresh_levante <- marks$levante_available_through >= required_levante
    fresh_com <- data.table::as.IDate(marks$com_complete_through) >= required_com_day
    reason <- if (existing) {
      "prediccion_existente"
    } else if (!fresh_levante) {
      "levantes_no_actualizado"
    } else if (!fresh_com) {
      "com_no_cerrado_para_features"
    } else {
      "procesado"
    }
    prediction_status <- if (existing) {
      "existente"
    } else if (fresh_levante && fresh_com) {
      "generada"
    } else {
      "no_generada"
    }
    controls[[index]] <- data.table::data.table(
      dia_objetivo = as.Date(target_day), estado_prediccion = prediction_status,
      motivo = reason, timestamp_minimo_levante = required_levante, fecha_reclamos_requerida = as.Date(required_com_day),
      timestamp_disponible_levante = marks$levante_available_through, fecha_com_cerrada_hasta = marks$com_complete_through
    )
    if (existing) {
      expected_clusters <- unique(daily[dia == target_day, cluster_id])
      scored_clusters <- prior[dia_objetivo == as.Date(target_day), cluster_id]
      if (!setequal(expected_clusters, scored_clusters)) {
        stop("Prediccion previa incompleta para ", as.Date(target_day))
      }
      safe_through <- target_day
      next
    }
    if (!fresh_levante || !fresh_com) {
      blocked <- TRUE
      next
    }

    scoring_universe <- if (is.null(universe_n)) {
      nrow(daily[dia == target_day])
    } else {
      universe_n
    }
    scored <- rf_score_com(daily[dia <= target_day], model, as.Date(target_day), scoring_universe)
    scored$timestamp_ejecucion <- Sys.time()
    new_predictions[[length(new_predictions) + 1L]] <- data.table::as.data.table(scored)
    safe_through <- target_day
  }

  additions <- data.table::rbindlist(new_predictions, fill = TRUE)
  all_predictions <- data.table::rbindlist(list(prior, additions), fill = TRUE)
  if (nrow(all_predictions)) {
    observed <- daily[dia <= data.table::as.IDate(marks$com_complete_through),
      .(cluster_id, dia_objetivo = as.Date(dia), tuvo_reclamo_observado = as.integer(tuvo_reclamo),
        n_reclamos_observado = as.integer(n_reclamos))]
    all_predictions[, dia_objetivo := as.Date(dia_objetivo)]
    all_predictions[observed, on = .(cluster_id, dia_objetivo), `:=`(
      tuvo_reclamo_observado = i.tuvo_reclamo_observado,
      n_reclamos_observado = i.n_reclamos_observado,
      estado_observacion = "cerrado"
    )]
    all_predictions[is.na(estado_observacion), estado_observacion := "pendiente"]
  }

  if (length(score_columns) && nrow(frozen_before)) {
    current_scores <- all_predictions[, c("dia_objetivo", "cluster_id", score_columns), with = FALSE]
    refreshed <- merge(frozen_before, current_scores, by = c("dia_objetivo", "cluster_id"),
      suffixes = c("_before", "_after"), sort = FALSE)
    for (column in score_columns) {
      if (!isTRUE(all.equal(refreshed[[paste0(column, "_before")]], refreshed[[paste0(column, "_after")]], tolerance = 0))) {
        stop("Se modifico una prediccion ya emitida: ", column)
      }
    }
  }

  state_closed_through <- min(safe_through, data.table::as.IDate(marks$com_complete_through)) - 2L
  if (state_closed_through < min(daily$dia)) {
    state_closed_through <- min(daily$dia)
  }
  updated_state <- if (safe_through == start_day) {
    state
  } else {
    rf_build_com_state(daily[dia <= safe_through], safe_through, min(state_closed_through, safe_through))
  }
  list(predictions = all_predictions, state = updated_state,
    controls = data.table::rbindlist(controls, fill = TRUE), state_day = as.Date(safe_through),
    state_closed_through = as.Date(unique(updated_state$fecha_reclamos_cerrada_hasta)))
}
