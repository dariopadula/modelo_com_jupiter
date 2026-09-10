auc_binaria <- function(y, score) {
  y <- as.integer(y)
  n_pos <- as.numeric(sum(y == 1L))
  n_neg <- as.numeric(sum(y == 0L))
  if (n_pos == 0L || n_neg == 0L) return(NA_real_)
  ranks <- rank(score, ties.method = "average")
  (sum(ranks[y == 1L]) - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg)
}

logloss_binaria <- function(y, p) {
  eps <- 1e-15
  p <- pmin(pmax(p, eps), 1 - eps)
  -mean(y * log(p) + (1 - y) * log(1 - p))
}

lift_top <- function(dt, score_col = "pred_prob", y_col = "target", cortes = c(0.01, 0.05, 0.10, 0.20)) {
  data.table::setorderv(dt, score_col, order = -1L)
  total_pos <- sum(dt[[y_col]] == 1L)
  base_rate <- mean(dt[[y_col]] == 1L)

  data.table::rbindlist(lapply(cortes, function(corte) {
    n_top <- max(1L, floor(nrow(dt) * corte))
    top <- dt[seq_len(n_top)]
    precision <- mean(top[[y_col]] == 1L)
    data.table::data.table(
      top_pct = corte,
      n = n_top,
      positivos = sum(top[[y_col]] == 1L),
      precision = precision,
      capture_rate = sum(top[[y_col]] == 1L) / total_pos,
      lift = precision / base_rate
    )
  }))
}

calibracion_deciles <- function(dt, score_col = "pred_prob", y_col = "target") {
  dt <- data.table::copy(dt)
  dt[, decil := data.table::frank(-get(score_col), ties.method = "average")]
  dt[, decil := ceiling(decil / .N * 10)]
  dt[, .(
    n = .N,
    pred_media = mean(get(score_col)),
    obs_rate = mean(get(y_col) == 1L),
    positivos = sum(get(y_col) == 1L)
  ), by = decil][order(decil)]
}

lift_diario_top <- function(dt, score_col = "pred_prob", y_col = "target", cortes = c(0.01, 0.05, 0.10, 0.20)) {
  data.table::rbindlist(lapply(sort(unique(dt$dia)), function(dia_i) {
    dt_dia <- data.table::copy(dt[dia == dia_i])
    data.table::setorderv(dt_dia, score_col, order = -1L)

    total_pos <- sum(dt_dia[[y_col]] == 1L)
    prevalencia <- mean(dt_dia[[y_col]] == 1L)

    data.table::rbindlist(lapply(cortes, function(corte) {
      n_top <- max(1L, floor(nrow(dt_dia) * corte))
      top <- dt_dia[seq_len(n_top)]
      positivos_top <- sum(top[[y_col]] == 1L)
      precision <- mean(top[[y_col]] == 1L)

      data.table::data.table(
        dia = dia_i,
        top_pct = corte,
        n_dia = nrow(dt_dia),
        positivos_dia = total_pos,
        prevalencia_dia = prevalencia,
        n_top = n_top,
        positivos_top = positivos_top,
        precision = precision,
        capture_rate = data.table::fifelse(total_pos > 0, positivos_top / total_pos, NA_real_),
        lift = data.table::fifelse(prevalencia > 0, precision / prevalencia, NA_real_),
        capture_rate_azar = corte
      )
    }))
  }))
}

graficar_capture_diario <- function(lift_diario, path_png) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    warning("El paquete ggplot2 no esta disponible; no se genera grafico")
    return(invisible(FALSE))
  }

  p <- ggplot2::ggplot(
    lift_diario[!is.na(capture_rate)],
    ggplot2::aes(x = capture_rate)
  ) +
    ggplot2::geom_histogram(
      bins = 20,
      fill = "#7aa6c2",
      color = "white"
    ) +
    ggplot2::geom_vline(
      ggplot2::aes(xintercept = capture_rate_azar),
      color = "#b13f3f",
      linewidth = 0.8
    ) +
    ggplot2::facet_wrap(
      ~ top_pct,
      scales = "free_x",
      labeller = ggplot2::label_both
    ) +
    ggplot2::labs(
      title = "Capture rate diario por corte de riesgo",
      x = "Capture rate diario",
      y = "Cantidad de dias",
      caption = "Linea roja: capture rate esperado por seleccion al azar"
    ) +
    ggplot2::theme_minimal(base_size = 11)

  ggplot2::ggsave(path_png, plot = p, width = 9, height = 6, dpi = 150)
  invisible(TRUE)
}

preparar_matriz <- function(dt, features, prep = NULL, no_agregar_na_features = character()) {
  x <- data.table::copy(dt[, ..features])

  for (col in names(x)) {
    if (is.logical(x[[col]])) x[, (col) := as.integer(get(col))]
    if (is.integer(x[[col]])) x[, (col) := as.numeric(get(col))]
  }

  if (is.null(prep)) {
    prep <- lapply(names(x), function(col) {
      vals <- x[[col]]
      med <- stats::median(vals, na.rm = TRUE)
      if (is.na(med) || is.infinite(med)) med <- 0
      vals_imp <- data.table::fifelse(is.na(vals), med, vals)
      media <- mean(vals_imp, na.rm = TRUE)
      desvio <- stats::sd(vals_imp, na.rm = TRUE)
      if (is.na(desvio) || desvio == 0) desvio <- 1
      list(
        col = col,
        mediana = med,
        media = media,
        desvio = desvio,
        agregar_na = any(is.na(vals)) && !col %in% no_agregar_na_features
      )
    })
    names(prep) <- names(x)
  }

  matrices <- list()
  for (col in names(x)) {
    p <- prep[[col]]
    vals <- x[[col]]
    if (isTRUE(p$agregar_na)) {
      matrices[[paste0(col, "_na")]] <- as.numeric(is.na(vals))
    }
    vals <- data.table::fifelse(is.na(vals), p$mediana, vals)
    matrices[[col]] <- (vals - p$media) / p$desvio
  }

  list(
    x = as.matrix(data.table::as.data.table(matrices)),
    prep = prep
  )
}

agregar_features_logistico_reducido <- function(dt) {
  dt <- data.table::copy(dt)

  dt[, `:=`(
    historia_observada_7_29 = dias_historia_observada_cluster >= 7 & dias_historia_observada_cluster <= 29,
    historia_observada_30_89 = dias_historia_observada_cluster >= 30 & dias_historia_observada_cluster <= 89,
    historia_observada_90_179 = dias_historia_observada_cluster >= 90 & dias_historia_observada_cluster <= 179,
    historia_observada_180_mas = dias_historia_observada_cluster >= 180,
    dias_desde_ultimo_reclamo_o_inicio_trunc_90 = pmin(dias_desde_ultimo_reclamo_o_inicio, 90)
  )]

  dt
}

agregar_features_exceso_levante_periodo <- function(dt,
                                                     truncar_max_dias = 7) {
  dt <- data.table::copy(dt)

  cols_req <- c("mean_tiempo_desde_ultimo_levante_pred", "mean_levante_periodo")
  faltantes <- setdiff(cols_req, names(dt))
  if (length(faltantes) > 0L) {
    stop("Faltan columnas para calcular exceso sobre periodo teorico: ", paste(faltantes, collapse = ", "))
  }

  dt[
    ,
    exceso_mean_tiempo_periodo_pred_pos := pmax(
      mean_tiempo_desde_ultimo_levante_pred - mean_levante_periodo,
      0
    )
  ]

  dt[
    ,
    exceso_mean_tiempo_periodo_pred_trunc_7 := pmin(
      exceso_mean_tiempo_periodo_pred_pos,
      truncar_max_dias
    )
  ]

  dt
}

aplicar_rezago_historia_reclamos <- function(dt,
                                             rezago_reclamos_dias = 1L,
                                             ventanas_dias = c(7L, 30L)) {
  dt <- data.table::copy(dt)
  rezago_reclamos_dias <- as.integer(rezago_reclamos_dias)

  cols_req <- c("cluster_id", "dia", "n_reclamos", "tuvo_reclamo")
  faltantes <- setdiff(cols_req, names(dt))
  if (length(faltantes) > 0L) {
    stop("Faltan columnas para recalcular historia de reclamos: ", paste(faltantes, collapse = ", "))
  }

  if (rezago_reclamos_dias < 1L) {
    stop("rezago_reclamos_dias debe ser >= 1")
  }

  dt[, dia := data.table::as.IDate(dia)]
  data.table::setorder(dt, cluster_id, dia)

  dt[, n_reclamos_hist_tmp := data.table::fifelse(is.na(n_reclamos), 0, n_reclamos)]
  dt[, tuvo_reclamo_hist_tmp := data.table::fifelse(is.na(tuvo_reclamo), FALSE, tuvo_reclamo)]

  dt[
    ,
    n_reclamos_lag1 := data.table::shift(n_reclamos_hist_tmp, rezago_reclamos_dias, fill = 0),
    by = cluster_id
  ]

  if ("tuvo_reclamo_lag1" %in% names(dt)) {
    dt[
      ,
      tuvo_reclamo_lag1 := data.table::shift(tuvo_reclamo_hist_tmp, rezago_reclamos_dias, fill = FALSE),
      by = cluster_id
    ]
  }

  dt[
    ,
    reclamos_previos_tmp := data.table::shift(n_reclamos_hist_tmp, rezago_reclamos_dias, fill = 0),
    by = cluster_id
  ]

  dt[
    ,
    tuvo_previos_tmp := as.integer(data.table::shift(tuvo_reclamo_hist_tmp, rezago_reclamos_dias, fill = FALSE)),
    by = cluster_id
  ]

  for (ventana in ventanas_dias) {
    col_sum <- paste0("n_reclamos_sum_", ventana, "d")
    col_tuvo <- paste0("tuvo_reclamo_sum_", ventana, "d")

    dt[
      ,
      (col_sum) := zoo::rollapplyr(reclamos_previos_tmp, width = ventana, FUN = sum, partial = TRUE, fill = NA),
      by = cluster_id
    ]

    if (col_tuvo %in% names(dt)) {
      dt[
        ,
        (col_tuvo) := zoo::rollapplyr(tuvo_previos_tmp, width = ventana, FUN = sum, partial = TRUE, fill = NA),
        by = cluster_id
      ]
    }
  }

  dt[
    ,
    dias_desde_ultimo_reclamo := {
      dias_reclamo_rezagados <- data.table::shift(
        data.table::fifelse(tuvo_reclamo_hist_tmp, dia, data.table::as.IDate(NA)),
        rezago_reclamos_dias
      )
      ultimo_reclamo <- zoo::na.locf(dias_reclamo_rezagados, na.rm = FALSE)
      as.numeric(dia - ultimo_reclamo)
    },
    by = cluster_id
  ]

  dt[, sin_reclamo_previo_observado := is.na(dias_desde_ultimo_reclamo)]

  if (!"dias_historia_observada_cluster" %in% names(dt)) {
    stop("Falta dias_historia_observada_cluster para recalcular dias_desde_ultimo_reclamo_o_inicio")
  }

  dt[, dias_desde_ultimo_reclamo_o_inicio := data.table::fifelse(
    sin_reclamo_previo_observado,
    dias_historia_observada_cluster,
    dias_desde_ultimo_reclamo
  )]

  cols_tmp <- c(
    "n_reclamos_hist_tmp",
    "tuvo_reclamo_hist_tmp",
    "reclamos_previos_tmp",
    "tuvo_previos_tmp"
  )
  dt[, (cols_tmp) := NULL]

  dt
}

definir_split_meses <- function(meses_disponibles,
                                n_train = 12L,
                                n_validacion = 3L,
                                n_test_min = 1L) {
  meses <- sort(unique(as.integer(meses_disponibles)))

  if (length(meses) < n_train + n_validacion) {
    stop("No hay meses suficientes para train y validacion")
  }

  if (length(meses) >= n_train + n_validacion + n_test_min) {
    meses_train <- meses[seq_len(n_train)]
    meses_validacion <- meses[seq.int(n_train + 1L, n_train + n_validacion)]
    meses_test <- meses[seq.int(n_train + n_validacion + 1L, length(meses))]
  } else {
    meses_train <- meses[seq_len(n_train)]
    meses_validacion <- meses[seq.int(n_train + 1L, length(meses))]
    meses_test <- integer()
  }

  list(
    meses = meses,
    meses_train = meses_train,
    meses_validacion = meses_validacion,
    meses_test = meses_test
  )
}

crear_folds_validacion_temporal <- function(meses_disponibles,
                                            n_train = 12L,
                                            meses_validacion_final = integer(),
                                            meses_test = integer()) {
  meses <- sort(unique(as.integer(meses_disponibles)))
  meses_excluidos_valid <- sort(unique(c(as.integer(meses_test))))
  meses_candidatos_valid <- setdiff(meses, meses_excluidos_valid)

  folds <- list()
  for (ii in seq.int(n_train + 1L, length(meses_candidatos_valid))) {
    mes_validacion <- meses_candidatos_valid[ii]
    meses_train <- meses_candidatos_valid[seq.int(ii - n_train, ii - 1L)]

    if (length(meses_validacion_final) > 0L && !mes_validacion %in% meses_validacion_final) {
      next
    }

    folds[[length(folds) + 1L]] <- list(
      fold = length(folds) + 1L,
      meses_train = meses_train,
      mes_validacion = mes_validacion
    )
  }

  folds
}
