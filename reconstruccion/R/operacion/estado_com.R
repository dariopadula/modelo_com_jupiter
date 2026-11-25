# Resume la memoria histórica COM a partir de features diarios preparados.
# Entrada: features hasta fecha_estado y corte contractual de reclamos.
# Salida: una fila por cluster con acumulados y recencia.
rf_build_com_state <- function(features, fecha_estado, fecha_reclamos_cerrada_hasta) {
  required <- c("cluster_id", "dia", "n_reclamos", "tuvo_reclamo", "n_contenedores_activos")
  missing <- setdiff(required, names(features))
  if (length(missing)) {
    stop("Faltan columnas para estado COM: ", paste(missing, collapse = ", "))
  }

  state_day <- data.table::as.IDate(fecha_estado)
  closed_day <- data.table::as.IDate(fecha_reclamos_cerrada_hasta)
  if (length(state_day) != 1L || is.na(state_day) || length(closed_day) != 1L || is.na(closed_day) ||
      closed_day > state_day) stop("Fechas de estado COM invalidas")

  daily <- data.table::copy(data.table::as.data.table(features))
  daily[, dia := data.table::as.IDate(dia)]
  daily <- daily[dia <= state_day]
  if (!nrow(daily)) {
    stop("No hay historia disponible para construir estado COM")
  }
  if (anyDuplicated(daily[, .(cluster_id, dia)])) {
    stop("Historia diaria COM duplicada")
  }
  daily[, cluster_existente := n_contenedores_activos > 0L]
  daily[is.na(cluster_existente), cluster_existente := FALSE]
  daily[, n_reclamos_estado := data.table::fifelse(is.na(n_reclamos), 0L, as.integer(n_reclamos))]
  daily[, reclamo_estado := !is.na(tuvo_reclamo) & as.logical(tuvo_reclamo)]

  state <- daily[, {
    observed_days <- dia[cluster_existente]
    closed_claim_days <- dia[reclamo_estado & dia <= closed_day]
    last_claim <- if (length(closed_claim_days)) {
      max(closed_claim_days)
    } else {
      data.table::as.IDate(NA)
    }
    history_days <- length(observed_days)
    no_claim <- is.na(last_claim)
    list(
      fecha_estado = state_day,
      fecha_reclamos_cerrada_hasta = closed_day,
      fecha_inicio_observacion_cluster = if (history_days) {
        min(observed_days)
      } else {
        data.table::as.IDate(NA)
      },
      dias_historia_observada_cluster = as.integer(history_days),
      fecha_ultimo_reclamo_cerrado = last_claim,
      sin_reclamo_previo_observado = no_claim,
      dias_desde_ultimo_reclamo_o_inicio = if (no_claim) {
        as.numeric(history_days)
      } else {
        as.numeric(state_day - last_claim)
      },
      n_reclamos_acumulados = as.integer(sum(n_reclamos_estado[dia <= closed_day], na.rm = TRUE)),
      dias_con_reclamo_acumulados = as.integer(sum(reclamo_estado & dia <= closed_day, na.rm = TRUE)),
      cluster_activo_fecha_estado = any(cluster_existente[dia == state_day]),
      n_contenedores_activos_fecha_estado = {
        active_counts <- n_contenedores_activos[dia == state_day]
        if (length(active_counts) && any(!is.na(active_counts))) {
          max(active_counts, na.rm = TRUE)
        } else {
          NA_integer_
        }
      },
      version_cluster = if ("version_cluster" %in% names(.SD)) {
        as.character(version_cluster[which.max(!is.na(version_cluster))])
      } else {
        NA_character_
      }
    )
  }, by = cluster_id]

  state[, dias_desde_ultimo_reclamo_o_inicio_trunc_90 := pmin(dias_desde_ultimo_reclamo_o_inicio, 90)]
  state[, historia_observada_7_29 := dias_historia_observada_cluster >= 7L & dias_historia_observada_cluster <= 29L]
  state[, historia_observada_30_89 := dias_historia_observada_cluster >= 30L & dias_historia_observada_cluster <= 89L]
  state[, historia_observada_90_179 := dias_historia_observada_cluster >= 90L & dias_historia_observada_cluster <= 179L]
  state[, historia_observada_180_mas := dias_historia_observada_cluster >= 180L]
  data.table::setorder(state, cluster_id)
  state
}
