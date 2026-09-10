combinar_fecha_hora <- function(fecha, hora, tz = "America/Montevideo") {
  as.POSIXct(
    paste(as.character(fecha), hora),
    tz = tz
  )
}

leer_dataset_si_existe <- function(path) {
  if (!dir.exists(path)) {
    return(NULL)
  }
  data.table::as.data.table(as.data.frame(arrow::open_dataset(path, format = "parquet")))
}

escribir_dataset_reemplazo <- function(dt, path, partitioning = NULL) {
  if (dir.exists(path)) {
    unlink(path, recursive = TRUE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  arrow::write_dataset(
    dt,
    path = path,
    format = "parquet",
    partitioning = partitioning,
    existing_data_behavior = "overwrite",
    compression = "zstd"
  )
}

leer_fecha_unica_estado <- function(estado_historico) {
  fechas <- unique(data.table::as.IDate(estado_historico$fecha_estado))
  if (length(fechas) != 1L || is.na(fechas)) {
    stop("El estado historico debe tener una unica fecha_estado valida")
  }
  fechas
}

resolver_plan_scoring <- function(fecha_estado, fecha_objetivo_hasta) {
  fecha_estado <- data.table::as.IDate(fecha_estado)
  fecha_objetivo_hasta <- data.table::as.IDate(fecha_objetivo_hasta)

  if (is.na(fecha_estado) || is.na(fecha_objetivo_hasta)) {
    stop("Las fechas del plan de scoring deben ser validas")
  }

  if (fecha_objetivo_hasta <= fecha_estado) {
    return(data.table::data.table(
      fecha_base_hasta = fecha_estado,
      fecha_actualizar_hasta = fecha_objetivo_hasta,
      dias_pendientes = 0L,
      requiere_scoring = FALSE
    ))
  }

  data.table::data.table(
    fecha_base_hasta = fecha_estado,
    fecha_actualizar_hasta = fecha_objetivo_hasta,
    dias_pendientes = as.integer(fecha_objetivo_hasta - fecha_estado),
    requiere_scoring = TRUE
  )
}

evaluar_frescura_scoring <- function(fecha_objetivo_hasta,
                                     timestamp_max_levante,
                                     fecha_com_cerrada_hasta,
                                     hora_corte_levantes = "01:00:00",
                                     rezago_reclamos_dias = 2L) {
  fecha_objetivo_hasta <- data.table::as.IDate(fecha_objetivo_hasta)
  fecha_com_cerrada_hasta <- data.table::as.IDate(fecha_com_cerrada_hasta)
  timestamp_minimo_levante <- combinar_fecha_hora(
    fecha_objetivo_hasta,
    hora_corte_levantes
  )
  fecha_reclamos_requerida <- fecha_objetivo_hasta - as.integer(rezago_reclamos_dias)

  estado_levante <- if (
    !is.na(timestamp_max_levante) &&
      timestamp_max_levante >= timestamp_minimo_levante
  ) {
    "ok"
  } else {
    "atrasado"
  }

  estado_com <- if (
    !is.na(fecha_com_cerrada_hasta) &&
      fecha_com_cerrada_hasta >= fecha_reclamos_requerida
  ) {
    "ok"
  } else {
    "atrasado"
  }

  data.table::data.table(
    fecha_objetivo_hasta = fecha_objetivo_hasta,
    timestamp_minimo_levante = timestamp_minimo_levante,
    timestamp_max_levante = timestamp_max_levante,
    estado_levante = estado_levante,
    fecha_reclamos_requerida = fecha_reclamos_requerida,
    fecha_com_cerrada_hasta = fecha_com_cerrada_hasta,
    estado_com = estado_com,
    puede_procesar = estado_levante == "ok" && estado_com == "ok"
  )
}

adquirir_lock_operativo <- function(path_lock,
                                    run_id,
                                    max_minutos = 180) {
  if (dir.exists(path_lock)) {
    info <- file.info(path_lock)
    antiguedad_minutos <- as.numeric(
      difftime(Sys.time(), info$mtime, units = "mins")
    )
    if (!is.na(antiguedad_minutos) && antiguedad_minutos > max_minutos) {
      unlink(path_lock, recursive = TRUE)
    } else {
      stop("Ya existe una corrida operativa activa: ", path_lock)
    }
  }

  if (!dir.create(path_lock, recursive = TRUE, showWarnings = FALSE)) {
    stop("No se pudo adquirir el lock operativo: ", path_lock)
  }

  saveRDS(
    list(
      run_id = run_id,
      timestamp_inicio = Sys.time(),
      pid = Sys.getpid()
    ),
    file.path(path_lock, "owner.rds")
  )
  invisible(TRUE)
}

liberar_lock_operativo <- function(path_lock) {
  if (dir.exists(path_lock)) {
    unlink(path_lock, recursive = TRUE)
  }
  invisible(TRUE)
}

publicar_directorio_transaccional <- function(path_nuevo,
                                              path_destino,
                                              path_backup) {
  if (!dir.exists(path_nuevo)) {
    return(invisible(FALSE))
  }

  dir.create(dirname(path_destino), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(path_backup), recursive = TRUE, showWarnings = FALSE)

  habia_destino <- dir.exists(path_destino)
  if (habia_destino && !file.rename(path_destino, path_backup)) {
    stop("No se pudo respaldar antes de publicar: ", path_destino)
  }

  publicado <- file.rename(path_nuevo, path_destino)
  if (!publicado) {
    if (habia_destino && dir.exists(path_backup)) {
      file.rename(path_backup, path_destino)
    }
    stop("No se pudo publicar el nuevo dataset: ", path_destino)
  }

  invisible(TRUE)
}

calcular_metricas_diarias_operativas <- function(predicciones,
                                                 cortes = c(0.01, 0.05, 0.10, 0.20)) {
  if (is.null(predicciones) || nrow(predicciones) == 0L || !"estado_observacion" %in% names(predicciones)) {
    return(data.table::data.table())
  }

  cerradas <- predicciones[estado_observacion == "cerrado"]
  if (nrow(cerradas) == 0L) {
    return(data.table::data.table())
  }

  data.table::rbindlist(lapply(sort(unique(cerradas$dia_objetivo)), function(dia_i) {
    dt_dia <- data.table::copy(cerradas[dia_objetivo == dia_i])
    data.table::setorder(dt_dia, ranking_dia)

    total_pos <- sum(dt_dia$tuvo_reclamo_observado == 1L, na.rm = TRUE)
    prevalencia <- mean(dt_dia$tuvo_reclamo_observado == 1L, na.rm = TRUE)

    data.table::rbindlist(lapply(cortes, function(corte) {
      n_top <- max(1L, floor(nrow(dt_dia) * corte))
      top <- dt_dia[seq_len(n_top)]
      positivos_top <- sum(top$tuvo_reclamo_observado == 1L, na.rm = TRUE)
      precision <- mean(top$tuvo_reclamo_observado == 1L, na.rm = TRUE)

      data.table::data.table(
        dia_objetivo = dia_i,
        top_pct = corte,
        n_dia = nrow(dt_dia),
        positivos_dia = total_pos,
        prevalencia_dia = prevalencia,
        n_top = n_top,
        positivos_top = positivos_top,
        precision = precision,
        capture_rate = data.table::fifelse(total_pos > 0, positivos_top / total_pos, NA_real_),
        lift = data.table::fifelse(prevalencia > 0, precision / prevalencia, NA_real_),
        modelo_id = unique(dt_dia$modelo_id),
        version_modelo = unique(dt_dia$version_modelo)
      )
    }))
  }))
}

agregar_ranking_operativo <- function(pred, score_col = "pred_prob") {
  pred <- data.table::copy(pred)
  data.table::setorderv(pred, c(score_col, "cluster_id"), order = c(-1L, 1L))
  pred[, ranking_dia := seq_len(.N)]
  pred[, percentil_riesgo := ranking_dia / .N]
  pred[, top_1 := percentil_riesgo <= 0.01]
  pred[, top_5 := percentil_riesgo <= 0.05]
  pred[, top_10 := percentil_riesgo <= 0.10]
  pred[, top_20 := percentil_riesgo <= 0.20]
  pred
}

generar_predicciones_logistico_operativo <- function(scoring,
                                                     modelo,
                                                     timestamp_corte_features,
                                                     timestamp_ejecucion,
                                                     modelo_id,
                                                     version_modelo,
                                                     version_cluster,
                                                     fecha_reclamos_usada_hasta,
                                                     timestamp_max_levante,
                                                     timestamp_max_com,
                                                     features_resumen = c(
                                                       "n_reclamos_lag1",
                                                       "n_reclamos_sum_7d",
                                                       "n_reclamos_sum_30d",
                                                       "dias_desde_ultimo_reclamo_o_inicio_trunc_90",
                                                       "mean_tiempo_desde_ultimo_levante_pred",
                                                       "n_contenedores_activos",
                                                       "pct_contenedores_inferidos"
                                                     )) {
  features_modelo <- modelo$features_modelo
  mat <- preparar_matriz(scoring, features_modelo, prep = modelo$prep)
  x <- cbind(intercept = 1, mat$x)
  pred_prob <- as.numeric(plogis(x %*% modelo$coeficientes_prediccion))

  cols_resumen <- intersect(features_resumen, names(scoring))
  pred <- scoring[, c(
    list(
      cluster_id = cluster_id,
      dia_objetivo = dia,
      anio_mes = anio_mes,
      modelo_id = modelo_id,
      version_modelo = version_modelo,
      version_cluster = version_cluster,
      timestamp_corte_features = timestamp_corte_features,
      timestamp_ejecucion = timestamp_ejecucion,
      pred_prob = pred_prob,
      fecha_reclamos_usada_hasta = fecha_reclamos_usada_hasta,
      timestamp_max_levante = timestamp_max_levante,
      timestamp_max_com = timestamp_max_com,
      estado_prediccion = "generada",
      tuvo_reclamo_observado = as.integer(NA),
      n_reclamos_observado = as.integer(NA),
      estado_observacion = "pendiente"
    ),
    .SD
  ), .SDcols = cols_resumen]

  agregar_ranking_operativo(pred)
}

actualizar_observados_operativos <- function(predicciones,
                                             datos_observados,
                                             fecha_com_cerrada_hasta,
                                             target_col = "tuvo_reclamo") {
  if (is.null(predicciones) || nrow(predicciones) == 0L) {
    return(predicciones)
  }

  observados <- datos_observados[
    dia <= fecha_com_cerrada_hasta,
    .(
      cluster_id,
      dia_objetivo = dia,
      tuvo_reclamo_observado_new = as.integer(get(target_col)),
      n_reclamos_observado_new = as.integer(n_reclamos)
    )
  ]

  predicciones <- observados[
    predicciones,
    on = .(cluster_id, dia_objetivo)
  ]

  predicciones[
    !is.na(tuvo_reclamo_observado_new),
    `:=`(
      tuvo_reclamo_observado = tuvo_reclamo_observado_new,
      n_reclamos_observado = n_reclamos_observado_new,
      estado_observacion = "cerrado"
    )
  ]
  predicciones[
    is.na(tuvo_reclamo_observado_new) & is.na(estado_observacion),
    estado_observacion := "pendiente"
  ]
  predicciones[, c("tuvo_reclamo_observado_new", "n_reclamos_observado_new") := NULL]

  predicciones
}

comparar_features_scoring <- function(features_calculadas,
                                      features_referencia,
                                      features_comparar,
                                      id_cols = c("cluster_id", "dia")) {
  calc <- data.table::copy(features_calculadas)
  ref <- data.table::copy(features_referencia)

  cols_calc <- intersect(c(id_cols, features_comparar), names(calc))
  cols_ref <- intersect(c(id_cols, features_comparar), names(ref))
  calc <- calc[, ..cols_calc]
  ref <- ref[, ..cols_ref]

  data.table::setnames(
    calc,
    setdiff(names(calc), id_cols),
    paste0(setdiff(names(calc), id_cols), "_calc")
  )
  data.table::setnames(
    ref,
    setdiff(names(ref), id_cols),
    paste0(setdiff(names(ref), id_cols), "_ref")
  )

  comp <- merge(calc, ref, by = id_cols, all = TRUE)

  data.table::rbindlist(lapply(features_comparar, function(feature) {
    col_calc <- paste0(feature, "_calc")
    col_ref <- paste0(feature, "_ref")
    if (!col_calc %in% names(comp) || !col_ref %in% names(comp)) {
      return(data.table::data.table(
        variable = feature,
        n_calc = sum(!is.na(comp[[col_calc]])),
        n_ref = sum(!is.na(comp[[col_ref]])),
        n_comparables = 0L,
        n_distintos = NA_integer_,
        pct_distintos = NA_real_,
        diff_abs_media = NA_real_,
        diff_abs_p95 = NA_real_,
        diff_abs_max = NA_real_
      ))
    }

    x <- comp[[col_calc]]
    y <- comp[[col_ref]]
    comparables <- !is.na(x) & !is.na(y)

    if (is.logical(x)) x <- as.integer(x)
    if (is.logical(y)) y <- as.integer(y)

    if (is.numeric(x) || is.integer(x)) {
      diff_abs <- abs(as.numeric(x) - as.numeric(y))
      distintos <- comparables & diff_abs > 1e-8
    } else {
      diff_abs <- rep(NA_real_, length(x))
      distintos <- comparables & as.character(x) != as.character(y)
    }

    data.table::data.table(
      variable = feature,
      n_calc = sum(!is.na(comp[[col_calc]])),
      n_ref = sum(!is.na(comp[[col_ref]])),
      n_comparables = sum(comparables),
      n_distintos = sum(distintos, na.rm = TRUE),
      pct_distintos = data.table::fifelse(sum(comparables) > 0, sum(distintos, na.rm = TRUE) / sum(comparables), NA_real_),
      diff_abs_media = if (any(comparables) && any(!is.na(diff_abs[comparables]))) mean(diff_abs[comparables], na.rm = TRUE) else NA_real_,
      diff_abs_p95 = if (any(comparables) && any(!is.na(diff_abs[comparables]))) as.numeric(stats::quantile(diff_abs[comparables], 0.95, na.rm = TRUE)) else NA_real_,
      diff_abs_max = if (any(comparables) && any(!is.na(diff_abs[comparables]))) max(diff_abs[comparables], na.rm = TRUE) else NA_real_
    )
  }), fill = TRUE)
}

construir_estado_historico_cluster <- function(datos_cluster_dia,
                                               fecha_estado,
                                               fecha_reclamos_cerrada_hasta = fecha_estado,
                                               target_col = "tuvo_reclamo") {
  dt <- data.table::copy(datos_cluster_dia)
  fecha_estado <- data.table::as.IDate(fecha_estado)
  fecha_reclamos_cerrada_hasta <- data.table::as.IDate(fecha_reclamos_cerrada_hasta)

  cols_req <- c("cluster_id", "dia", "n_reclamos", target_col)
  faltantes <- setdiff(cols_req, names(dt))
  if (length(faltantes) > 0L) {
    stop("Faltan columnas para construir estado historico: ", paste(faltantes, collapse = ", "))
  }

  dt[, dia := data.table::as.IDate(dia)]
  dt <- dt[dia <= fecha_estado]

  if (!"cluster_existente_dia" %in% names(dt)) {
    if (!"n_contenedores_activos" %in% names(dt)) {
      stop("Falta cluster_existente_dia o n_contenedores_activos")
    }
    dt[, cluster_existente_dia := n_contenedores_activos >= 1L]
  }

  dt[, cluster_existente_dia := data.table::fifelse(is.na(cluster_existente_dia), FALSE, cluster_existente_dia)]
  dt[, n_reclamos := data.table::fifelse(is.na(n_reclamos), 0L, as.integer(n_reclamos))]
  dt[, tuvo_reclamo_estado_tmp := data.table::fifelse(is.na(get(target_col)), FALSE, get(target_col))]

  estado_base <- dt[
    ,
    {
      dias_existente <- dia[cluster_existente_dia == TRUE]
      dias_reclamo <- dia[tuvo_reclamo_estado_tmp == TRUE & dia <= fecha_reclamos_cerrada_hasta]

      fecha_inicio <- if (length(dias_existente) > 0L) min(dias_existente) else data.table::as.IDate(NA)
      fecha_ultimo_reclamo <- if (length(dias_reclamo) > 0L) max(dias_reclamo) else data.table::as.IDate(NA)
      sin_reclamo <- is.na(fecha_ultimo_reclamo)
      dias_historia <- sum(cluster_existente_dia == TRUE, na.rm = TRUE)

      data.table::data.table(
        fecha_estado = fecha_estado,
        fecha_reclamos_cerrada_hasta = fecha_reclamos_cerrada_hasta,
        fecha_inicio_observacion_cluster = fecha_inicio,
        dias_historia_observada_cluster = as.integer(dias_historia),
        fecha_ultimo_reclamo_cerrado = fecha_ultimo_reclamo,
        sin_reclamo_previo_observado = sin_reclamo,
        dias_desde_ultimo_reclamo_o_inicio = if (sin_reclamo) {
          as.numeric(dias_historia)
        } else {
          as.numeric(fecha_estado - fecha_ultimo_reclamo)
        },
        n_reclamos_acumulados = as.integer(sum(
          n_reclamos[dia <= fecha_reclamos_cerrada_hasta],
          na.rm = TRUE
        )),
        dias_con_reclamo_acumulados = as.integer(sum(
          tuvo_reclamo_estado_tmp == TRUE & dia <= fecha_reclamos_cerrada_hasta,
          na.rm = TRUE
        ))
      )
    },
    by = cluster_id
  ]

  estado_dia <- dt[
    dia == fecha_estado,
    .(
      cluster_activo_fecha_estado = any(cluster_existente_dia == TRUE, na.rm = TRUE),
      n_contenedores_activos_fecha_estado = if ("n_contenedores_activos" %in% names(dt)) {
        suppressWarnings(max(n_contenedores_activos, na.rm = TRUE))
      } else {
        NA_integer_
      }
    ),
    by = cluster_id
  ]
  estado_dia[is.infinite(n_contenedores_activos_fecha_estado), n_contenedores_activos_fecha_estado := NA_real_]

  estado <- estado_dia[
    estado_base,
    on = "cluster_id"
  ]
  estado[is.na(cluster_activo_fecha_estado), cluster_activo_fecha_estado := FALSE]

  if ("version_cluster" %in% names(dt)) {
    versiones <- dt[, .(version_cluster = version_cluster[which.max(!is.na(version_cluster))]), by = cluster_id]
    estado <- versiones[estado, on = "cluster_id"]
  }

  estado[, dias_desde_ultimo_reclamo_o_inicio_trunc_90 := pmin(dias_desde_ultimo_reclamo_o_inicio, 90)]
  estado[, historia_observada_7_29 := dias_historia_observada_cluster >= 7 & dias_historia_observada_cluster <= 29]
  estado[, historia_observada_30_89 := dias_historia_observada_cluster >= 30 & dias_historia_observada_cluster <= 89]
  estado[, historia_observada_90_179 := dias_historia_observada_cluster >= 90 & dias_historia_observada_cluster <= 179]
  estado[, historia_observada_180_mas := dias_historia_observada_cluster >= 180]

  data.table::setorder(estado, cluster_id)
  estado
}

actualizar_estado_historico_cluster <- function(estado_anterior,
                                                datos_nuevos_cluster_dia,
                                                nueva_fecha_estado,
                                                nueva_fecha_reclamos_cerrada_hasta,
                                                target_col = "tuvo_reclamo") {
  estado <- data.table::copy(estado_anterior)
  nuevos <- data.table::copy(datos_nuevos_cluster_dia)
  nueva_fecha_estado <- data.table::as.IDate(nueva_fecha_estado)
  nueva_fecha_reclamos_cerrada_hasta <- data.table::as.IDate(nueva_fecha_reclamos_cerrada_hasta)

  if (nrow(estado) == 0L) {
    return(construir_estado_historico_cluster(
      datos_cluster_dia = nuevos,
      fecha_estado = nueva_fecha_estado,
      fecha_reclamos_cerrada_hasta = nueva_fecha_reclamos_cerrada_hasta,
      target_col = target_col
    ))
  }

  fecha_estado_anterior <- unique(data.table::as.IDate(estado$fecha_estado))
  fecha_reclamos_anterior <- unique(data.table::as.IDate(estado$fecha_reclamos_cerrada_hasta))

  if (length(fecha_estado_anterior) != 1L || length(fecha_reclamos_anterior) != 1L) {
    stop("El estado anterior debe corresponder a una unica fecha de estado y cierre de reclamos")
  }
  if (nueva_fecha_estado < fecha_estado_anterior) {
    stop("nueva_fecha_estado no puede ser anterior al estado existente")
  }
  if (nueva_fecha_reclamos_cerrada_hasta < fecha_reclamos_anterior) {
    stop("La fecha cerrada de reclamos no puede retroceder")
  }
  if (nueva_fecha_reclamos_cerrada_hasta > nueva_fecha_estado) {
    stop("La fecha cerrada de reclamos no puede superar la fecha de estado")
  }

  cols_req <- c("cluster_id", "dia", "n_reclamos", target_col)
  faltantes <- setdiff(cols_req, names(nuevos))
  if (length(faltantes) > 0L) {
    stop("Faltan columnas para actualizar estado historico: ", paste(faltantes, collapse = ", "))
  }

  nuevos[, dia := data.table::as.IDate(dia)]
  if (!"cluster_existente_dia" %in% names(nuevos)) {
    if (!"n_contenedores_activos" %in% names(nuevos)) {
      stop("Falta cluster_existente_dia o n_contenedores_activos")
    }
    nuevos[, cluster_existente_dia := n_contenedores_activos >= 1L]
  }
  nuevos[, cluster_existente_dia := data.table::fifelse(is.na(cluster_existente_dia), FALSE, cluster_existente_dia)]
  nuevos[, n_reclamos := data.table::fifelse(is.na(n_reclamos), 0L, as.integer(n_reclamos))]
  nuevos[, tuvo_reclamo_estado_tmp := data.table::fifelse(is.na(get(target_col)), FALSE, get(target_col))]

  clusters_nuevos <- setdiff(unique(nuevos$cluster_id), estado$cluster_id)
  if (length(clusters_nuevos) > 0L) {
    estado_nuevos <- construir_estado_historico_cluster(
      datos_cluster_dia = nuevos[cluster_id %in% clusters_nuevos],
      fecha_estado = nueva_fecha_estado,
      fecha_reclamos_cerrada_hasta = nueva_fecha_reclamos_cerrada_hasta,
      target_col = target_col
    )
    estado <- data.table::rbindlist(list(estado, estado_nuevos), fill = TRUE)
  }

  incremento_historia <- nuevos[
    !cluster_id %in% clusters_nuevos &
    dia > fecha_estado_anterior &
      dia <= nueva_fecha_estado &
      cluster_existente_dia == TRUE,
    .(dias_historia_incremento = .N),
    by = cluster_id
  ]

  reclamos_incremento <- nuevos[
    !cluster_id %in% clusters_nuevos &
    dia > fecha_reclamos_anterior &
      dia <= nueva_fecha_reclamos_cerrada_hasta,
    .(
      n_reclamos_incremento = as.integer(sum(n_reclamos, na.rm = TRUE)),
      dias_con_reclamo_incremento = as.integer(sum(tuvo_reclamo_estado_tmp == TRUE, na.rm = TRUE)),
      fecha_ultimo_reclamo_incremento = {
        dias <- dia[tuvo_reclamo_estado_tmp == TRUE]
        if (length(dias) > 0L) max(dias) else data.table::as.IDate(NA)
      }
    ),
    by = cluster_id
  ]

  estado_dia <- nuevos[
    dia == nueva_fecha_estado,
    .(
      cluster_activo_fecha_estado_new = any(cluster_existente_dia == TRUE, na.rm = TRUE),
      n_contenedores_activos_fecha_estado_new = if ("n_contenedores_activos" %in% names(nuevos)) {
        suppressWarnings(max(n_contenedores_activos, na.rm = TRUE))
      } else {
        NA_integer_
      }
    ),
    by = cluster_id
  ]
  estado_dia[
    is.infinite(n_contenedores_activos_fecha_estado_new),
    n_contenedores_activos_fecha_estado_new := NA_real_
  ]

  estado <- incremento_historia[estado, on = "cluster_id"]
  estado <- reclamos_incremento[estado, on = "cluster_id"]
  estado <- estado_dia[estado, on = "cluster_id"]

  estado[, dias_historia_observada_cluster := as.integer(
    data.table::fcoalesce(dias_historia_observada_cluster, 0L) +
      data.table::fcoalesce(dias_historia_incremento, 0L)
  )]
  estado[, n_reclamos_acumulados := as.integer(
    data.table::fcoalesce(n_reclamos_acumulados, 0L) +
      data.table::fcoalesce(n_reclamos_incremento, 0L)
  )]
  estado[, dias_con_reclamo_acumulados := as.integer(
    data.table::fcoalesce(dias_con_reclamo_acumulados, 0L) +
      data.table::fcoalesce(dias_con_reclamo_incremento, 0L)
  )]

  estado[
    !is.na(fecha_ultimo_reclamo_incremento),
    fecha_ultimo_reclamo_cerrado := fecha_ultimo_reclamo_incremento
  ]
  estado[, fecha_ultimo_reclamo_cerrado := data.table::as.IDate(fecha_ultimo_reclamo_cerrado)]

  estado[, cluster_activo_fecha_estado := FALSE]
  estado[, n_contenedores_activos_fecha_estado := as.numeric(NA)]
  estado[
    !is.na(cluster_activo_fecha_estado_new),
    cluster_activo_fecha_estado := cluster_activo_fecha_estado_new
  ]
  estado[
    !is.na(n_contenedores_activos_fecha_estado_new),
    n_contenedores_activos_fecha_estado := n_contenedores_activos_fecha_estado_new
  ]
  estado[is.na(cluster_activo_fecha_estado), cluster_activo_fecha_estado := FALSE]

  estado[, `:=`(
    fecha_estado = nueva_fecha_estado,
    fecha_reclamos_cerrada_hasta = nueva_fecha_reclamos_cerrada_hasta,
    sin_reclamo_previo_observado = is.na(fecha_ultimo_reclamo_cerrado)
  )]
  estado[, dias_desde_ultimo_reclamo_o_inicio := data.table::fifelse(
    sin_reclamo_previo_observado,
    dias_historia_observada_cluster,
    as.numeric(nueva_fecha_estado - fecha_ultimo_reclamo_cerrado)
  )]
  estado[, dias_desde_ultimo_reclamo_o_inicio_trunc_90 := pmin(dias_desde_ultimo_reclamo_o_inicio, 90)]
  estado[, historia_observada_7_29 := dias_historia_observada_cluster >= 7 & dias_historia_observada_cluster <= 29]
  estado[, historia_observada_30_89 := dias_historia_observada_cluster >= 30 & dias_historia_observada_cluster <= 89]
  estado[, historia_observada_90_179 := dias_historia_observada_cluster >= 90 & dias_historia_observada_cluster <= 179]
  estado[, historia_observada_180_mas := dias_historia_observada_cluster >= 180]

  cols_tmp <- c(
    "dias_historia_incremento",
    "n_reclamos_incremento",
    "dias_con_reclamo_incremento",
    "fecha_ultimo_reclamo_incremento",
    "cluster_activo_fecha_estado_new",
    "n_contenedores_activos_fecha_estado_new"
  )
  estado[, (intersect(cols_tmp, names(estado))) := NULL]
  data.table::setorder(estado, cluster_id)
  estado
}

aplicar_estado_historico_a_features <- function(features_scoring,
                                                estado_historico,
                                                fecha_reclamos_usada_hasta,
                                                target_col = "tuvo_reclamo") {
  features <- data.table::copy(features_scoring)
  estado <- data.table::copy(estado_historico)
  fecha_reclamos_usada_hasta <- data.table::as.IDate(fecha_reclamos_usada_hasta)

  features[, dia := data.table::as.IDate(dia)]
  features[, dias_historia_ventana_tmp := dias_historia_observada_cluster]
  estado[, fecha_estado := data.table::as.IDate(fecha_estado)]
  estado[, fecha_ultimo_reclamo_cerrado := data.table::as.IDate(fecha_ultimo_reclamo_cerrado)]

  reclamos_ventana <- features[
    dia <= fecha_reclamos_usada_hasta & get(target_col) == TRUE,
    .(fecha_ultimo_reclamo_ventana = max(dia)),
    by = cluster_id
  ]

  estado_cols <- c(
    "cluster_id",
    "fecha_inicio_observacion_cluster",
    "dias_historia_observada_cluster",
    "fecha_ultimo_reclamo_cerrado",
    "sin_reclamo_previo_observado"
  )
  estado <- estado[, ..estado_cols]

  features <- estado[features, on = "cluster_id"]
  features <- reclamos_ventana[features, on = "cluster_id"]

  features[, dias_historia_observada_cluster := data.table::fcoalesce(
    dias_historia_observada_cluster,
    dias_historia_ventana_tmp
  )]
  features[, fecha_ultimo_reclamo_operativo := data.table::fifelse(
    !is.na(fecha_ultimo_reclamo_ventana) &
      (is.na(fecha_ultimo_reclamo_cerrado) | fecha_ultimo_reclamo_ventana > fecha_ultimo_reclamo_cerrado),
    fecha_ultimo_reclamo_ventana,
    fecha_ultimo_reclamo_cerrado
  )]
  features[, fecha_ultimo_reclamo_operativo := data.table::as.IDate(fecha_ultimo_reclamo_operativo)]

  features[, sin_reclamo_previo_observado := is.na(fecha_ultimo_reclamo_operativo)]
  features[, dias_desde_ultimo_reclamo := as.numeric(dia - fecha_ultimo_reclamo_operativo)]
  features[, dias_desde_ultimo_reclamo_o_inicio := data.table::fifelse(
    sin_reclamo_previo_observado,
    dias_historia_observada_cluster,
    dias_desde_ultimo_reclamo
  )]
  features[, dias_desde_ultimo_reclamo_o_inicio_trunc_90 := pmin(dias_desde_ultimo_reclamo_o_inicio, 90)]

  features[, historia_observada_7_29 := dias_historia_observada_cluster >= 7 & dias_historia_observada_cluster <= 29]
  features[, historia_observada_30_89 := dias_historia_observada_cluster >= 30 & dias_historia_observada_cluster <= 89]
  features[, historia_observada_90_179 := dias_historia_observada_cluster >= 90 & dias_historia_observada_cluster <= 179]
  features[, historia_observada_180_mas := dias_historia_observada_cluster >= 180]

  features[, c(
    "dias_historia_ventana_tmp",
    "fecha_ultimo_reclamo_ventana",
    "fecha_ultimo_reclamo_cerrado",
    "fecha_ultimo_reclamo_operativo",
    "fecha_inicio_observacion_cluster"
  ) := NULL]

  features
}
