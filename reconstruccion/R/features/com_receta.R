# Receta migrada de funciones/modelos_utils.R; procedencia R03.

# Aplica imputacion y estandarizacion de la receta de entrenamiento.  Entradas: tabla,
# variables y prep opcional. Salida: matriz numerica y prep.

# Aplica imputacion y estandarizacion de la receta de entrenamiento.  Entradas: tabla,
# variables y prep opcional. Salida: matriz numerica y prep.
preparar_matriz <- function(dt, features, prep = NULL, no_agregar_na_features = character()) {
  x <- data.table::copy(dt[, ..features])
  for (col in names(x)) {
    if (is.logical(x[[col]]))
      x[, `:=`((col), as.integer(get(col)))]
    if (is.integer(x[[col]]))
      x[, `:=`((col), as.numeric(get(col)))]
  }
  if (is.null(prep)) {
    prep <- lapply(names(x), function(col) {
      vals <- x[[col]]
      med <- stats::median(vals, na.rm = TRUE)
      if (is.na(med) || is.infinite(med))
        med <- 0
      vals_imp <- data.table::fifelse(is.na(vals), med, vals)
      media <- mean(vals_imp, na.rm = TRUE)
      desvio <- stats::sd(vals_imp, na.rm = TRUE)
      if (is.na(desvio) || desvio == 0)
        desvio <- 1
      list(col = col, mediana = med, media = media, desvio = desvio, agregar_na = any(is.na(vals)) &&
        !col %in% no_agregar_na_features)
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
    matrices[[col]] <- (vals - p$media)/p$desvio
  }
  list(x = as.matrix(data.table::as.data.table(matrices)), prep = prep)
}


# Deriva categorias de historia y recencia truncada para COM.  Entrada: tabla
# historica. Salida: copia con features derivadas.

# Deriva categorias de historia y recencia truncada para COM.  Entrada: tabla
# historica. Salida: copia con features derivadas.
agregar_features_logistico_reducido <- function(dt) {
  dt <- data.table::copy(dt)
  dt[, `:=`(historia_observada_7_29 = dias_historia_observada_cluster >= 7 & dias_historia_observada_cluster <=
    29, historia_observada_30_89 = dias_historia_observada_cluster >= 30 & dias_historia_observada_cluster <=
    89, historia_observada_90_179 = dias_historia_observada_cluster >= 90 & dias_historia_observada_cluster <=
    179, historia_observada_180_mas = dias_historia_observada_cluster >= 180, dias_desde_ultimo_reclamo_o_inicio_trunc_90 = pmin(dias_desde_ultimo_reclamo_o_inicio,
    90))]
  dt
}


# Reconstruye historia COM rezagada sin usar eventos del dia objetivo.  Entradas: tabla
# por cluster/dia, rezago y ventanas. Salida: copia con historia recalculada.

# Reconstruye historia COM rezagada sin usar eventos del dia objetivo.  Entradas: tabla
# por cluster/dia, rezago y ventanas. Salida: copia con historia recalculada.
aplicar_rezago_historia_reclamos <- function(dt, rezago_reclamos_dias = 1L, ventanas_dias = c(7L,
  30L)) {
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
  dt[, `:=`(dia, data.table::as.IDate(dia))]
  data.table::setorder(dt, cluster_id, dia)
  dt[, `:=`(n_reclamos_hist_tmp, data.table::fifelse(is.na(n_reclamos), 0, n_reclamos))]
  dt[, `:=`(tuvo_reclamo_hist_tmp, data.table::fifelse(is.na(tuvo_reclamo), FALSE, tuvo_reclamo))]
  dt[, `:=`(n_reclamos_lag1, data.table::shift(n_reclamos_hist_tmp, rezago_reclamos_dias,
    fill = 0)), by = cluster_id]
  if ("tuvo_reclamo_lag1" %in% names(dt)) {
    dt[, `:=`(tuvo_reclamo_lag1, data.table::shift(tuvo_reclamo_hist_tmp, rezago_reclamos_dias,
      fill = FALSE)), by = cluster_id]
  }
  dt[, `:=`(reclamos_previos_tmp, data.table::shift(n_reclamos_hist_tmp, rezago_reclamos_dias,
    fill = 0)), by = cluster_id]
  dt[, `:=`(tuvo_previos_tmp, as.integer(data.table::shift(tuvo_reclamo_hist_tmp, rezago_reclamos_dias,
    fill = FALSE))), by = cluster_id]
  for (ventana in ventanas_dias) {
    col_sum <- paste0("n_reclamos_sum_", ventana, "d")
    col_tuvo <- paste0("tuvo_reclamo_sum_", ventana, "d")
    dt[, `:=`((col_sum), {
      acumulado <- cumsum(reclamos_previos_tmp)
      acumulado - data.table::shift(acumulado, ventana, fill = 0)
    }), by = cluster_id]
    if (col_tuvo %in% names(dt)) {
      dt[, `:=`((col_tuvo), {
        acumulado <- cumsum(tuvo_previos_tmp)
        acumulado - data.table::shift(acumulado, ventana, fill = 0)
      }), by = cluster_id]
    }
  }
  dt[, `:=`(dias_desde_ultimo_reclamo, {
    dia_entero <- as.integer(dia)
    dias_reclamo_rezagados <- data.table::shift(data.table::fifelse(tuvo_reclamo_hist_tmp,
      dia_entero, NA_integer_), rezago_reclamos_dias)
    ultimo_reclamo <- data.table::nafill(dias_reclamo_rezagados, type = "locf")
    as.numeric(dia_entero - ultimo_reclamo)
  }), by = cluster_id]
  dt[, `:=`(sin_reclamo_previo_observado, is.na(dias_desde_ultimo_reclamo))]
  if (!"dias_historia_observada_cluster" %in% names(dt)) {
    stop("Falta dias_historia_observada_cluster para recalcular dias_desde_ultimo_reclamo_o_inicio")
  }
  dt[, `:=`(dias_desde_ultimo_reclamo_o_inicio, data.table::fifelse(sin_reclamo_previo_observado,
    dias_historia_observada_cluster, dias_desde_ultimo_reclamo))]
  cols_tmp <- c("n_reclamos_hist_tmp", "tuvo_reclamo_hist_tmp", "reclamos_previos_tmp",
    "tuvo_previos_tmp")
  dt[, `:=`((cols_tmp), NULL)]
  dt
}
