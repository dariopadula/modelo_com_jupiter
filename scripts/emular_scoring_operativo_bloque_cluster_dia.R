library(arrow)
library(data.table)

source("funciones/modelos_utils.R")
source("funciones/scoring_operativo_utils.R")
source("funciones/construir_base_cluster_dia.R")
source("funciones/construir_features_historicas_cluster_dia.R")

################################
### Parametros
path_levante <- Sys.getenv("PATH_LEVANTE", unset = "data/parquet/levante")
path_asignaciones_com <- Sys.getenv(
  "PATH_ASIGNACIONES_COM",
  unset = "data/processed/com_contenedor_cluster/asignaciones_com"
)
path_cluster_actual <- Sys.getenv(
  "PATH_CLUSTER_ACTUAL",
  unset = "data/processed/cluster_update_check/contenedor_posicion_cluster_actual"
)
path_features_referencia <- Sys.getenv(
  "PATH_FEATURES_REFERENCIA",
  unset = "data/processed/modelo_cluster_dia/features_cluster_dia"
)
path_predicciones_existentes <- Sys.getenv(
  "PATH_PREDICCIONES_EXISTENTES",
  unset = ""
)
path_control_existente <- Sys.getenv(
  "PATH_CONTROL_EXISTENTE",
  unset = ""
)
path_estado_historico <- Sys.getenv(
  "PATH_ESTADO_HISTORICO",
  unset = "data/processed/app_emulacion/estado_historico_cluster"
)
path_modelo <- Sys.getenv(
  "PATH_MODELO",
  unset = "data/processed/modelos/logistico_cluster_dia_reducido_reclamos_d2/modelo_logistico_reducido.rds"
)
out_base <- Sys.getenv(
  "OUT_BASE_APP",
  unset = "data/processed/app_emulacion_bloque"
)

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
modelo_id_param <- Sys.getenv("MODELO_ID", unset = "logistico_reducido_d2_bloque")
version_modelo_param <- Sys.getenv("VERSION_MODELO", unset = "v2026_06_09")
target_col <- "tuvo_reclamo"

fecha_base_hasta <- data.table::as.IDate(Sys.getenv("FECHA_BASE_HASTA", unset = "2025-12-31"))
fecha_actualizar_hasta <- data.table::as.IDate(Sys.getenv("FECHA_ACTUALIZAR_HASTA", unset = NA_character_))
hora_corte_levantes <- Sys.getenv("HORA_CORTE_LEVANTES", unset = "01:00:00")
rezago_reclamos_dias <- as.integer(Sys.getenv("REZAGO_RECLAMOS_DIAS", unset = "2"))
ventana_dias <- as.integer(Sys.getenv("VENTANA_DIAS", unset = "120"))
forzar_reproceso <- tolower(Sys.getenv("FORZAR_REPROCESO", unset = "FALSE")) %in% c("true", "1", "si")
comparar_referencia <- tolower(
  Sys.getenv("COMPARAR_REFERENCIA", unset = "TRUE")
) %in% c("true", "1", "si")

fecha_fuente_levante_hasta <- data.table::as.IDate(
  Sys.getenv("FECHA_FUENTE_LEVANTE_HASTA", unset = NA_character_)
)
fecha_com_cerrada_hasta <- data.table::as.IDate(
  Sys.getenv("FECHA_COM_CERRADA_HASTA", unset = NA_character_)
)

redondeo_m <- 1
estados_com_validos <- c("asignado", "revision")
usar_solo_contenedor_dia_elegible_modelo <- TRUE
cortes_top <- c(0.01, 0.05, 0.10, 0.20)
timestamp_ejecucion <- Sys.time()

out_predicciones <- file.path(out_base, "predicciones_operativas_cluster_dia")
out_control <- file.path(out_base, "control_scoring")
out_metricas <- file.path(out_base, "metricas_diarias")
out_comparacion_features <- file.path(out_base, "comparacion_features_referencia")
out_estado_final <- file.path(out_base, "estado_historico_final")
out_resumen_corrida <- file.path(out_base, "resumen_corrida")

if (is.na(fecha_actualizar_hasta)) {
  stop("Debe definir FECHA_ACTUALIZAR_HASTA")
}
if (fecha_actualizar_hasta <= fecha_base_hasta) {
  stop("FECHA_ACTUALIZAR_HASTA debe ser mayor que FECHA_BASE_HASTA")
}
if (rezago_reclamos_dias < 1L) {
  stop("REZAGO_RECLAMOS_DIAS debe ser mayor o igual a 1")
}
if (ventana_dias < 30L) {
  stop("VENTANA_DIAS debe ser al menos 30")
}

################################
### Cargo modelo y fuentes una sola vez
tiempo_total <- system.time({
  modelo <- readRDS(path_modelo)
  features_modelo <- modelo$features_modelo

  datos_levante <- as.data.table(arrow::open_dataset(path_levante, format = "parquet"))
  asignaciones_com <- as.data.table(arrow::open_dataset(path_asignaciones_com, format = "parquet"))
  contenedor_posicion_cluster <- as.data.table(
    arrow::open_dataset(path_cluster_actual, format = "parquet")
  )
  features_referencia <- if (comparar_referencia) {
    as.data.table(arrow::open_dataset(path_features_referencia, format = "parquet"))
  } else {
    data.table()
  }
  estado_historico <- as.data.table(
    arrow::open_dataset(path_estado_historico, format = "parquet")
  )

  if (!is.na(target_version_cluster) && target_version_cluster != "") {
    asignaciones_com <- asignaciones_com[version_cluster == target_version_cluster]
    contenedor_posicion_cluster <- contenedor_posicion_cluster[
      version_cluster == target_version_cluster
    ]
    if (comparar_referencia) {
      features_referencia <- features_referencia[version_cluster == target_version_cluster]
    }
    estado_historico <- estado_historico[version_cluster == target_version_cluster]
  } else {
    versiones <- sort(unique(contenedor_posicion_cluster$version_cluster))
    target_version_cluster <- versiones[length(versiones)]
    asignaciones_com <- asignaciones_com[version_cluster == target_version_cluster]
    contenedor_posicion_cluster <- contenedor_posicion_cluster[
      version_cluster == target_version_cluster
    ]
    if (comparar_referencia) {
      features_referencia <- features_referencia[version_cluster == target_version_cluster]
    }
    estado_historico <- estado_historico[version_cluster == target_version_cluster]
  }

  datos_levante[, dia := data.table::as.IDate(dia)]
  asignaciones_com[, dia := data.table::as.IDate(dia)]
  if (comparar_referencia) {
    features_referencia[, dia := data.table::as.IDate(dia)]
  }
  estado_historico[, `:=`(
    fecha_estado = data.table::as.IDate(fecha_estado),
    fecha_reclamos_cerrada_hasta = data.table::as.IDate(fecha_reclamos_cerrada_hasta)
  )]

  fecha_estado_inicial <- unique(estado_historico$fecha_estado)
  fecha_reclamos_inicial <- unique(estado_historico$fecha_reclamos_cerrada_hasta)
  if (length(fecha_estado_inicial) != 1L || fecha_estado_inicial != fecha_base_hasta) {
    stop("El estado historico inicial no coincide con FECHA_BASE_HASTA")
  }
  if (length(fecha_reclamos_inicial) != 1L) {
    stop("El estado historico debe tener una unica fecha de cierre de reclamos")
  }

  features_referencia_d2 <- if (comparar_referencia) {
    referencia <- aplicar_rezago_historia_reclamos(
      features_referencia,
      rezago_reclamos_dias = rezago_reclamos_dias
    )
    agregar_features_logistico_reducido(referencia)
  } else {
    data.table()
  }

  timestamp_max_levante <- max(
    as.POSIXct(datos_levante$fecha_levante, tz = "America/Montevideo"),
    na.rm = TRUE
  )
  timestamp_max_com <- if ("fecha_de_reclamo" %in% names(asignaciones_com)) {
    max(
      as.POSIXct(asignaciones_com$fecha_de_reclamo, tz = "America/Montevideo"),
      na.rm = TRUE
    )
  } else {
    combinar_fecha_hora(max(asignaciones_com$dia, na.rm = TRUE), "23:59:59")
  }

  if (!is.na(fecha_fuente_levante_hasta)) {
    timestamp_max_levante <- combinar_fecha_hora(fecha_fuente_levante_hasta, "23:59:59")
  }
  if (!is.na(fecha_com_cerrada_hasta)) {
    timestamp_max_com <- combinar_fecha_hora(fecha_com_cerrada_hasta, "23:59:59")
  } else {
    fecha_com_cerrada_hasta <- data.table::as.IDate(as.Date(timestamp_max_com)) - 1L
  }

  dias_objetivo <- seq(fecha_base_hasta + 1L, fecha_actualizar_hasta, by = "day")
  fecha_inicio_ventana <- min(dias_objetivo) - ventana_dias

  ################################
  ### Construyo una unica ventana para todo el bloque
  tiempo_features_bloque <- system.time({
    levante_bloque <- datos_levante[
      dia >= fecha_inicio_ventana & dia <= fecha_actualizar_hasta
    ]
    com_bloque <- asignaciones_com[
      dia >= fecha_inicio_ventana & dia <= fecha_actualizar_hasta
    ]

    base_bloque <- construir_base_cluster_dia(
      datos_levante = levante_bloque,
      asignaciones_com = com_bloque,
      contenedor_posicion_cluster = contenedor_posicion_cluster,
      redondeo_m = redondeo_m,
      estados_com_validos = estados_com_validos,
      limitar_rango_fechas_com = FALSE,
      usar_solo_contenedor_dia_elegible_modelo = usar_solo_contenedor_dia_elegible_modelo
    )$base_cluster_dia

    features_bloque_sin_rezago <- construir_features_historicas_cluster_dia(
      base_cluster_dia = base_bloque,
      ventanas_dias = c(7L, 30L)
    )$features_cluster_dia

    features_bloque <- aplicar_rezago_historia_reclamos(
      features_bloque_sin_rezago,
      rezago_reclamos_dias = rezago_reclamos_dias
    )
    features_bloque <- agregar_features_logistico_reducido(features_bloque)
  })

  path_pred_lectura <- if (
    path_predicciones_existentes != "" &&
      dir.exists(path_predicciones_existentes)
  ) {
    path_predicciones_existentes
  } else {
    out_predicciones
  }
  predicciones_existentes <- leer_dataset_si_existe(path_pred_lectura)
  if (!is.null(predicciones_existentes)) {
    predicciones_existentes[, dia_objetivo := data.table::as.IDate(dia_objetivo)]
  }

  predicciones_nuevas <- list()
  control <- list()
  comparacion_features <- list()
  estado_actual <- data.table::copy(estado_historico)

  ################################
  ### Recorro dias sin reconstruir la ventana
  tiempo_recorrido_dias <- system.time({
    for (dia_i in dias_objetivo) {
      dia_i <- data.table::as.IDate(dia_i)
      timestamp_minimo_levante <- combinar_fecha_hora(dia_i, hora_corte_levantes)
      fecha_reclamos_usada_hasta <- dia_i - rezago_reclamos_dias

      existe_prediccion <- !is.null(predicciones_existentes) &&
        nrow(predicciones_existentes[
          dia_objetivo == dia_i &
            modelo_id == modelo_id_param &
            version_modelo == version_modelo_param
        ]) > 0L

      estado_levante <- data.table::fifelse(
        timestamp_max_levante >= timestamp_minimo_levante,
        "ok",
        "atrasado"
      )
      estado_com_features <- data.table::fifelse(
        fecha_com_cerrada_hasta >= fecha_reclamos_usada_hasta,
        "ok",
        "atrasado"
      )
      puede_generar <- estado_levante == "ok" && estado_com_features == "ok"

      estado_prediccion <- "generada"
      motivo <- "ok"
      n_predicciones <- 0L
      n_referencia <- 0L
      diff_media <- NA_real_
      diff_p95 <- NA_real_
      diff_max <- NA_real_

      if (existe_prediccion && !forzar_reproceso) {
        estado_prediccion <- "ya_existia"
        motivo <- "prediccion_existente"
      } else if (!puede_generar) {
        estado_prediccion <- "no_generada"
        motivo <- paste(
          c(
            if (estado_levante != "ok") "levantes_no_actualizado",
            if (estado_com_features != "ok") "com_no_cerrado_para_features"
          ),
          collapse = ";"
        )
      } else {
        features_dia <- aplicar_estado_historico_a_features(
          features_scoring = features_bloque[dia <= dia_i],
          estado_historico = estado_actual,
          fecha_reclamos_usada_hasta = fecha_reclamos_usada_hasta,
          target_col = target_col
        )
        scoring <- data.table::copy(features_dia[dia == dia_i])
        referencia_dia <- if (comparar_referencia) {
          data.table::copy(features_referencia_d2[dia == dia_i])
        } else {
          data.table()
        }

        if (nrow(scoring) == 0L) {
          estado_prediccion <- "no_generada"
          motivo <- "sin_filas_scoring"
        } else {
          faltantes <- setdiff(features_modelo, names(scoring))
          if (length(faltantes) > 0L) {
            stop("Faltan features en scoring por bloque: ", paste(faltantes, collapse = ", "))
          }

          if (comparar_referencia) {
            comp_dia <- comparar_features_scoring(
              features_calculadas = scoring,
              features_referencia = referencia_dia,
              features_comparar = features_modelo
            )
            comp_dia[, `:=`(
              dia_objetivo = dia_i,
              ventana_dias = ventana_dias,
              fecha_inicio_ventana = fecha_inicio_ventana,
              modelo_id = modelo_id_param,
              version_modelo = version_modelo_param
            )]
            comparacion_features[[length(comparacion_features) + 1L]] <- comp_dia
          }

          pred <- generar_predicciones_logistico_operativo(
            scoring = scoring,
            modelo = modelo,
            timestamp_corte_features = timestamp_minimo_levante,
            timestamp_ejecucion = timestamp_ejecucion,
            modelo_id = modelo_id_param,
            version_modelo = version_modelo_param,
            version_cluster = target_version_cluster,
            fecha_reclamos_usada_hasta = fecha_reclamos_usada_hasta,
            timestamp_max_levante = timestamp_max_levante,
            timestamp_max_com = timestamp_max_com
          )

          if (comparar_referencia && nrow(referencia_dia) > 0L) {
            pred_ref <- generar_predicciones_logistico_operativo(
              scoring = referencia_dia,
              modelo = modelo,
              timestamp_corte_features = timestamp_minimo_levante,
              timestamp_ejecucion = timestamp_ejecucion,
              modelo_id = modelo_id_param,
              version_modelo = version_modelo_param,
              version_cluster = target_version_cluster,
              fecha_reclamos_usada_hasta = fecha_reclamos_usada_hasta,
              timestamp_max_levante = timestamp_max_levante,
              timestamp_max_com = timestamp_max_com
            )[, .(cluster_id, pred_prob_ref = pred_prob, ranking_dia_ref = ranking_dia)]
            pred <- pred_ref[pred, on = "cluster_id"]
          } else {
            pred[, `:=`(
              pred_prob_ref = NA_real_,
              ranking_dia_ref = NA_integer_
            )]
          }

          pred[, `:=`(
            pred_prob_diff_abs_ref = abs(pred_prob - pred_prob_ref),
            ranking_diff_abs_ref = abs(ranking_dia - ranking_dia_ref),
            fecha_inicio_ventana = fecha_inicio_ventana,
            ventana_dias = ventana_dias
          )]
          predicciones_nuevas[[length(predicciones_nuevas) + 1L]] <- pred

          n_predicciones <- nrow(pred)
          n_referencia <- nrow(referencia_dia)
          if (comparar_referencia && any(!is.na(pred$pred_prob_diff_abs_ref))) {
            diff_media <- mean(pred$pred_prob_diff_abs_ref, na.rm = TRUE)
            diff_p95 <- as.numeric(
              stats::quantile(pred$pred_prob_diff_abs_ref, 0.95, na.rm = TRUE)
            )
            diff_max <- max(pred$pred_prob_diff_abs_ref, na.rm = TRUE)
          }
        }
      }

      control[[length(control) + 1L]] <- data.table(
        dia_objetivo = dia_i,
        timestamp_ejecucion = timestamp_ejecucion,
        modelo_id = modelo_id_param,
        version_modelo = version_modelo_param,
        estado_prediccion = estado_prediccion,
        motivo = motivo,
        fecha_inicio_ventana = fecha_inicio_ventana,
        ventana_dias = ventana_dias,
        timestamp_minimo_levante = timestamp_minimo_levante,
        timestamp_max_levante = timestamp_max_levante,
        estado_levante = estado_levante,
        fecha_reclamos_usada_hasta = fecha_reclamos_usada_hasta,
        fecha_com_cerrada_hasta = fecha_com_cerrada_hasta,
        timestamp_max_com = timestamp_max_com,
        estado_com_features = estado_com_features,
        n_predicciones = n_predicciones,
        n_referencia = n_referencia,
        pred_prob_diff_abs_media_ref = diff_media,
        pred_prob_diff_abs_p95_ref = diff_p95,
        pred_prob_diff_abs_max_ref = diff_max
      )

      if (puede_generar) {
        estado_actual <- actualizar_estado_historico_cluster(
          estado_anterior = estado_actual,
          datos_nuevos_cluster_dia = features_bloque_sin_rezago[
            dia > min(fecha_estado_inicial, fecha_reclamos_inicial) &
              dia <= dia_i
          ],
          nueva_fecha_estado = dia_i,
          nueva_fecha_reclamos_cerrada_hasta = min(
            dia_i - 1L,
            fecha_com_cerrada_hasta
          ),
          target_col = target_col
        )
      }
    }
  })

  predicciones_nuevas <- data.table::rbindlist(predicciones_nuevas, fill = TRUE)
  control <- data.table::rbindlist(control, fill = TRUE)
  comparacion_features <- data.table::rbindlist(comparacion_features, fill = TRUE)

  predicciones_final <- data.table::rbindlist(
    list(predicciones_existentes, predicciones_nuevas),
    fill = TRUE
  )

  if (nrow(predicciones_final) > 0L) {
    data.table::setorder(
      predicciones_final,
      dia_objetivo,
      modelo_id,
      version_modelo,
      cluster_id,
      -timestamp_ejecucion
    )
    predicciones_final <- unique(
      predicciones_final,
      by = c("dia_objetivo", "modelo_id", "version_modelo", "cluster_id")
    )
    datos_observados <- if (comparar_referencia) {
      features_referencia_d2
    } else {
      features_bloque_sin_rezago
    }
    predicciones_final <- actualizar_observados_operativos(
      predicciones = predicciones_final,
      datos_observados = datos_observados,
      fecha_com_cerrada_hasta = fecha_com_cerrada_hasta,
      target_col = target_col
    )
  }

  metricas_diarias <- calcular_metricas_diarias_operativas(
    predicciones_final,
    cortes_top
  )
})

################################
### Guardo resultados
resumen_corrida <- data.table(
  fecha_base_hasta = fecha_base_hasta,
  fecha_actualizar_hasta = fecha_actualizar_hasta,
  dias_objetivo = length(dias_objetivo),
  fecha_inicio_ventana = fecha_inicio_ventana,
  ventana_dias = ventana_dias,
  rezago_reclamos_dias = rezago_reclamos_dias,
  version_cluster = target_version_cluster,
  modelo_id = modelo_id_param,
  version_modelo = version_modelo_param,
  predicciones_nuevas = nrow(predicciones_nuevas),
  predicciones_acumuladas = nrow(predicciones_final),
  segundos_construccion_features_bloque = as.numeric(tiempo_features_bloque[["elapsed"]]),
  segundos_recorrido_dias = as.numeric(tiempo_recorrido_dias[["elapsed"]]),
  segundos_total = as.numeric(tiempo_total[["elapsed"]])
)

dir.create(out_base, recursive = TRUE, showWarnings = FALSE)

if (nrow(predicciones_final) > 0L) {
  escribir_dataset_reemplazo(
    predicciones_final,
    out_predicciones,
    partitioning = c("modelo_id", "version_modelo", "anio_mes")
  )
}
if (nrow(control) > 0L) {
  control_existente <- if (
    path_control_existente != "" &&
      dir.exists(path_control_existente)
  ) {
    leer_dataset_si_existe(path_control_existente)
  } else {
    NULL
  }
  control <- data.table::rbindlist(list(control_existente, control), fill = TRUE)
  escribir_dataset_reemplazo(
    control,
    out_control,
    partitioning = c("modelo_id", "version_modelo")
  )
}
if (nrow(metricas_diarias) > 0L) {
  escribir_dataset_reemplazo(
    metricas_diarias,
    out_metricas,
    partitioning = c("modelo_id", "version_modelo")
  )
}
if (nrow(comparacion_features) > 0L) {
  escribir_dataset_reemplazo(
    comparacion_features,
    out_comparacion_features,
    partitioning = c("modelo_id", "version_modelo")
  )
}

estado_actual[, version_cluster := target_version_cluster]
escribir_dataset_reemplazo(
  estado_actual,
  out_estado_final,
  partitioning = c("version_cluster", "fecha_estado")
)
escribir_dataset_reemplazo(resumen_corrida, out_resumen_corrida)

################################
### Salida de control
print(resumen_corrida)
print(control)
if (nrow(comparacion_features) > 0L) {
  print(comparacion_features[order(-pct_distintos)][1:min(.N, 20L)])
}
if (nrow(metricas_diarias) > 0L) {
  print(metricas_diarias)
}
