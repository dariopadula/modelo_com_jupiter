construir_features_historicas_cluster_dia <- function(base_cluster_dia,
                                                      ventanas_dias = c(7L, 30L)) {
  data.table::setDT(base_cluster_dia)

  cols_req <- c("cluster_id", "dia", "n_reclamos", "tuvo_reclamo")
  if (!all(cols_req %in% names(base_cluster_dia))) {
    stop("base_cluster_dia debe tener columnas: ", paste(cols_req, collapse = ", "))
  }

  base <- data.table::copy(base_cluster_dia)
  base[, dia := data.table::as.IDate(dia)]
  data.table::setorder(base, cluster_id, dia)

  base[, cluster_existente_dia := n_contenedores_activos >= 1L]

  rango_dias <- seq(min(base$dia, na.rm = TRUE), max(base$dia, na.rm = TRUE), by = "day")
  cluster_dias <- data.table::CJ(
    cluster_id = unique(base$cluster_id),
    dia = rango_dias,
    unique = TRUE
  )

  hist <- base[
    cluster_dias,
    on = .(cluster_id, dia)
  ][
    ,
    .(
      cluster_id,
      dia,
      n_reclamos_hist = data.table::fifelse(is.na(n_reclamos), 0, n_reclamos),
      tuvo_reclamo_hist = data.table::fifelse(is.na(tuvo_reclamo), FALSE, tuvo_reclamo),
      cluster_existente_hist = data.table::fifelse(is.na(cluster_existente_dia), FALSE, cluster_existente_dia)
    )
  ]

  data.table::setorder(hist, cluster_id, dia)
  hist[, n_reclamos_lag1 := data.table::shift(n_reclamos_hist, 1L, fill = 0), by = cluster_id]
  hist[, tuvo_reclamo_lag1 := data.table::shift(tuvo_reclamo_hist, 1L, fill = FALSE), by = cluster_id]

  hist[
    ,
    reclamos_previos := data.table::shift(n_reclamos_hist, 1L, fill = 0),
    by = cluster_id
  ]
  hist[
    ,
    tuvo_previos := as.integer(data.table::shift(tuvo_reclamo_hist, 1L, fill = FALSE)),
    by = cluster_id
  ]
  hist[
    ,
    existente_previos := as.integer(data.table::shift(cluster_existente_hist, 1L, fill = FALSE)),
    by = cluster_id
  ]
  hist[
    ,
    dias_historia_observada_cluster := cumsum(existente_previos),
    by = cluster_id
  ]

  for (ventana in ventanas_dias) {
    col_sum <- paste0("n_reclamos_sum_", ventana, "d")
    col_tuvo <- paste0("tuvo_reclamo_sum_", ventana, "d")
    col_dias <- paste0("dias_cluster_existente_", ventana, "d")
    col_pct <- paste0("pct_dias_cluster_existente_", ventana, "d")

    hist[, (col_sum) := {
      acumulado <- cumsum(reclamos_previos)
      acumulado - data.table::shift(acumulado, ventana, fill = 0)
    }, by = cluster_id]

    hist[, (col_tuvo) := {
      acumulado <- cumsum(tuvo_previos)
      acumulado - data.table::shift(acumulado, ventana, fill = 0)
    }, by = cluster_id]

    hist[, (col_dias) := {
      acumulado <- cumsum(existente_previos)
      acumulado - data.table::shift(acumulado, ventana, fill = 0)
    }, by = cluster_id]

    hist[, (col_pct) := get(col_dias) / ventana]
  }

  hist[
    ,
    dias_desde_ultimo_reclamo := {
      dia_entero <- as.integer(dia)
      dias_reclamo_previos <- data.table::shift(
        data.table::fifelse(tuvo_reclamo_hist, dia_entero, NA_integer_),
        1L
      )
      ultimo_reclamo <- data.table::nafill(dias_reclamo_previos, type = "locf")
      as.numeric(dia_entero - ultimo_reclamo)
    },
    by = cluster_id
  ]
  hist[, sin_reclamo_previo_observado := is.na(dias_desde_ultimo_reclamo)]
  hist[, dias_desde_ultimo_reclamo_o_inicio := data.table::fifelse(
    sin_reclamo_previo_observado,
    dias_historia_observada_cluster,
    dias_desde_ultimo_reclamo
  )]

  cols_hist <- c(
    "n_reclamos_lag1",
    "tuvo_reclamo_lag1",
    "dias_desde_ultimo_reclamo",
    "sin_reclamo_previo_observado",
    "dias_historia_observada_cluster",
    "dias_desde_ultimo_reclamo_o_inicio",
    unlist(lapply(ventanas_dias, function(ventana) {
      c(
        paste0("n_reclamos_sum_", ventana, "d"),
        paste0("tuvo_reclamo_sum_", ventana, "d"),
        paste0("dias_cluster_existente_", ventana, "d"),
        paste0("pct_dias_cluster_existente_", ventana, "d")
      )
    }))
  )

  base <- hist[base, on = .(cluster_id, dia)][, c(cols_hist, names(base)), with = FALSE]

  base[, anio := as.integer(format(dia, "%Y"))]
  base[, anio_mes := as.integer(format(dia, "%Y%m"))]

  resumen <- data.table::rbindlist(list(
    data.table::data.table(metrica = "filas_features_cluster_dia", valor = nrow(base)),
    data.table::data.table(metrica = "clusters", valor = data.table::uniqueN(base$cluster_id)),
    data.table::data.table(metrica = "dias", valor = data.table::uniqueN(base$dia)),
    data.table::data.table(metrica = "cluster_dia_con_reclamo", valor = sum(base$tuvo_reclamo)),
    data.table::data.table(metrica = "reclamos", valor = sum(base$n_reclamos)),
    data.table::data.table(metrica = "features_historicas", valor = length(ventanas_dias) * 4L + 6L)
  ))

  list(
    features_cluster_dia = base,
    resumen = resumen
  )
}
