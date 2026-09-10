library(arrow)
library(data.table)

source("funciones/scoring_operativo_utils.R")

################################
### Configuracion
path_levante <- Sys.getenv("PATH_LEVANTE", unset = "data/parquet/levante")
path_asignaciones_com <- Sys.getenv(
  "PATH_ASIGNACIONES_COM",
  unset = "data/processed/com_contenedor_cluster/asignaciones_com"
)
path_cluster_actual <- Sys.getenv(
  "PATH_CLUSTER_ACTUAL",
  unset = "data/processed/cluster_update_check/contenedor_posicion_cluster_actual"
)
path_modelo <- Sys.getenv(
  "PATH_MODELO",
  unset = "data/processed/modelos/logistico_cluster_dia_reducido_reclamos_d2/modelo_logistico_reducido.rds"
)
path_estado_inicial <- Sys.getenv(
  "PATH_ESTADO_INICIAL",
  unset = "data/processed/app_emulacion/estado_historico_cluster"
)
out_base <- Sys.getenv("OUT_BASE_APP", unset = "data/processed/app")

fecha_objetivo_hasta <- data.table::as.IDate(
  Sys.getenv(
    "FECHA_OBJETIVO_HASTA",
    unset = as.character(as.Date(Sys.time(), tz = "America/Montevideo"))
  )
)
hora_corte_levantes <- Sys.getenv("HORA_CORTE_LEVANTES", unset = "01:00:00")
rezago_reclamos_dias <- as.integer(
  Sys.getenv("REZAGO_RECLAMOS_DIAS", unset = "2")
)
ventana_dias <- as.integer(Sys.getenv("VENTANA_DIAS", unset = "120"))
modelo_id <- Sys.getenv("MODELO_ID", unset = "logistico_reducido_d2")
version_modelo <- Sys.getenv("VERSION_MODELO", unset = "v2026_06_09")
version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
solo_validar <- tolower(
  Sys.getenv("SOLO_VALIDAR", unset = "FALSE")
) %in% c("true", "1", "si")
max_minutos_lock <- as.numeric(
  Sys.getenv("MAX_MINUTOS_LOCK", unset = "180")
)
path_staging_reanudar <- Sys.getenv("PATH_STAGING_REANUDAR", unset = "")

fecha_fuente_levante_hasta <- data.table::as.IDate(
  Sys.getenv("FECHA_FUENTE_LEVANTE_HASTA", unset = NA_character_)
)
fecha_com_cerrada_hasta_param <- data.table::as.IDate(
  Sys.getenv("FECHA_COM_CERRADA_HASTA", unset = NA_character_)
)

timestamp_inicio <- Sys.time()
run_id <- paste0(
  format(timestamp_inicio, "%Y%m%dT%H%M%S"),
  "_",
  Sys.getpid()
)

path_predicciones <- file.path(out_base, "predicciones_operativas_cluster_dia")
path_estado <- file.path(out_base, "estado_historico_cluster")
path_control <- file.path(out_base, "control_scoring")
path_metricas <- file.path(out_base, "metricas_diarias")
path_control_ejecuciones <- file.path(out_base, "control_ejecuciones")
path_lock <- file.path(out_base, ".scoring_operativo.lock")
path_staging <- if (
  path_staging_reanudar != "" &&
    dir.exists(path_staging_reanudar)
) {
  path_staging_reanudar
} else {
  file.path(out_base, ".staging", run_id)
}
path_backup <- file.path(out_base, ".backups", run_id)

ejecutar_proceso <- function() {
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
adquirir_lock_operativo(path_lock, run_id, max_minutos = max_minutos_lock)
on.exit(liberar_lock_operativo(path_lock), add = TRUE)

guardar_control_ejecucion <- function(registro) {
  existente <- leer_dataset_si_existe(path_control_ejecuciones)
  final <- data.table::rbindlist(list(existente, registro), fill = TRUE)
  escribir_dataset_reemplazo(
    final,
    path_control_ejecuciones,
    partitioning = "estado_ejecucion"
  )
}

validar_columnas <- function(dt, requeridas, fuente) {
  faltantes <- setdiff(requeridas, names(dt))
  if (length(faltantes) > 0L) {
    stop(
      "La fuente ",
      fuente,
      " no cumple el contrato. Faltan: ",
      paste(faltantes, collapse = ", ")
    )
  }
}

construir_observados_operativos <- function(predicciones,
                                            asignaciones_com,
                                            fecha_cerrada) {
  if (is.null(predicciones) || nrow(predicciones) == 0L) {
    return(data.table())
  }

  claves <- unique(predicciones[
    dia_objetivo <= fecha_cerrada,
    .(cluster_id, dia = dia_objetivo)
  ])
  if (nrow(claves) == 0L) {
    return(data.table())
  }

  reclamos <- asignaciones_com[
    dia <= fecha_cerrada &
      estado_asignacion_com %in% c("asignado", "revision") &
      !is.na(cluster_id),
    .(n_reclamos = uniqueN(id)),
    by = .(cluster_id, dia)
  ]

  observados <- reclamos[claves, on = .(cluster_id, dia)]
  observados[is.na(n_reclamos), n_reclamos := 0L]
  observados[, tuvo_reclamo := n_reclamos > 0L]
  observados
}

################################
### Preflight y contratos
resultado <- tryCatch({
  datos_levante <- as.data.table(
    arrow::open_dataset(path_levante, format = "parquet")
  )
  asignaciones_com <- as.data.table(
    arrow::open_dataset(path_asignaciones_com, format = "parquet")
  )
  mapa_cluster <- as.data.table(
    arrow::open_dataset(path_cluster_actual, format = "parquet")
  )

  validar_columnas(
    datos_levante,
    c(
      "levante_contenedor_id",
      "dia",
      "fecha_levante",
      "x",
      "y",
      "contenedor_activo_dia"
    ),
    "levantes"
  )
  validar_columnas(
    asignaciones_com,
    c(
      "id",
      "dia",
      "cluster_id",
      "estado_asignacion_com"
    ),
    "reclamos asignados"
  )
  validar_columnas(
    mapa_cluster,
    c("levante_contenedor_id", "x", "y", "cluster_id", "version_cluster"),
    "mapa de clusters"
  )
  if (!file.exists(path_modelo)) {
    stop("No existe el modelo: ", path_modelo)
  }

  datos_levante[, dia := data.table::as.IDate(dia)]
  asignaciones_com[, dia := data.table::as.IDate(dia)]

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
    timestamp_max_levante <- combinar_fecha_hora(
      fecha_fuente_levante_hasta,
      "23:59:59"
    )
  }
  fecha_com_cerrada_hasta <- if (!is.na(fecha_com_cerrada_hasta_param)) {
    fecha_com_cerrada_hasta_param
  } else {
    data.table::as.IDate(max(asignaciones_com$dia, na.rm = TRUE)) - 1L
  }

  path_estado_lectura <- if (dir.exists(path_estado)) {
    path_estado
  } else {
    path_estado_inicial
  }
  estado_inicial <- leer_dataset_si_existe(path_estado_lectura)
  if (is.null(estado_inicial) || nrow(estado_inicial) == 0L) {
    stop("No existe un estado historico inicial utilizable")
  }

  if (!is.na(version_cluster) && version_cluster != "") {
    version_cluster_objetivo <- version_cluster
    estado_inicial <- estado_inicial[
      get("version_cluster") == version_cluster_objetivo
    ]
    mapa_cluster <- mapa_cluster[
      get("version_cluster") == version_cluster_objetivo
    ]
    asignaciones_com <- asignaciones_com[
      get("version_cluster") == version_cluster_objetivo
    ]
  } else {
    versiones <- sort(unique(mapa_cluster$version_cluster))
    version_cluster <- versiones[length(versiones)]
    version_cluster_objetivo <- version_cluster
    estado_inicial <- estado_inicial[
      get("version_cluster") == version_cluster_objetivo
    ]
    asignaciones_com <- asignaciones_com[
      get("version_cluster") == version_cluster_objetivo
    ]
  }

  fecha_estado <- leer_fecha_unica_estado(estado_inicial)
  plan <- resolver_plan_scoring(fecha_estado, fecha_objetivo_hasta)
  frescura <- evaluar_frescura_scoring(
    fecha_objetivo_hasta = fecha_objetivo_hasta,
    timestamp_max_levante = timestamp_max_levante,
    fecha_com_cerrada_hasta = fecha_com_cerrada_hasta,
    hora_corte_levantes = hora_corte_levantes,
    rezago_reclamos_dias = rezago_reclamos_dias
  )

  preflight <- cbind(
    data.table(
      run_id = run_id,
      timestamp_inicio = timestamp_inicio,
      fecha_estado = fecha_estado,
      dias_pendientes = plan$dias_pendientes,
      version_cluster = version_cluster,
      modelo_id = modelo_id,
      version_modelo = version_modelo
    ),
    frescura
  )
  print(preflight)

  if (solo_validar) {
    guardar_control_ejecucion(preflight[, `:=`(
      timestamp_fin = Sys.time(),
      estado_ejecucion = "solo_validacion",
      mensaje = "Contratos, plan y frescura validados"
    )])
    return(invisible(preflight))
  }

  if (plan$requiere_scoring && !frescura$puede_procesar) {
    guardar_control_ejecucion(preflight[, `:=`(
      timestamp_fin = Sys.time(),
      estado_ejecucion = "bloqueada_fuentes",
      mensaje = paste(
        c(
          if (frescura$estado_levante != "ok") "levantes_atrasados",
          if (frescura$estado_com != "ok") "reclamos_no_cerrados"
        ),
        collapse = ";"
      )
    )])
    stop("No se procesa: las fuentes no cumplen los umbrales de frescura")
  }

  ################################
  ### Scoring de dias pendientes en staging
  if (plan$requiere_scoring) {
    staging_reutilizable <- all(dir.exists(file.path(
      path_staging,
      c("predicciones_operativas_cluster_dia", "estado_historico_final")
    )))

    if (!staging_reutilizable) {
      dir.create(path_staging, recursive = TRUE, showWarnings = FALSE)
      variables_bloque <- c(
        PATH_LEVANTE = path_levante,
        PATH_ASIGNACIONES_COM = path_asignaciones_com,
        PATH_CLUSTER_ACTUAL = path_cluster_actual,
        PATH_ESTADO_HISTORICO = path_estado_lectura,
        PATH_MODELO = path_modelo,
        PATH_PREDICCIONES_EXISTENTES = if (dir.exists(path_predicciones)) {
          path_predicciones
        } else {
          ""
        },
        PATH_CONTROL_EXISTENTE = if (dir.exists(path_control)) path_control else "",
        OUT_BASE_APP = path_staging,
        FECHA_BASE_HASTA = as.character(fecha_estado),
        FECHA_ACTUALIZAR_HASTA = as.character(fecha_objetivo_hasta),
        HORA_CORTE_LEVANTES = hora_corte_levantes,
        REZAGO_RECLAMOS_DIAS = as.character(rezago_reclamos_dias),
        VENTANA_DIAS = as.character(ventana_dias),
        MODELO_ID = modelo_id,
        VERSION_MODELO = version_modelo,
        VERSION_CLUSTER = version_cluster,
        FECHA_FUENTE_LEVANTE_HASTA = as.character(
          data.table::as.IDate(as.Date(
            timestamp_max_levante,
            tz = "America/Montevideo"
          ))
        ),
        FECHA_COM_CERRADA_HASTA = as.character(fecha_com_cerrada_hasta),
        COMPARAR_REFERENCIA = "FALSE",
        FORZAR_REPROCESO = "FALSE"
      )
      anteriores <- Sys.getenv(names(variables_bloque), unset = NA_character_)
      do.call(Sys.setenv, as.list(variables_bloque))
      on.exit({
        restaurar <- !is.na(anteriores)
        if (any(restaurar)) {
          do.call(Sys.setenv, as.list(anteriores[restaurar]))
        }
        if (any(!restaurar)) {
          Sys.unsetenv(names(anteriores)[!restaurar])
        }
      }, add = TRUE)

      entorno_bloque <- new.env(parent = globalenv())
      sys.source(
        "scripts/emular_scoring_operativo_bloque_cluster_dia.R",
        envir = entorno_bloque
      )
    } else {
      message("Reanudando desde staging existente: ", path_staging)
    }
  } else {
    dir.create(path_staging, recursive = TRUE, showWarnings = FALSE)
    if (dir.exists(path_predicciones)) {
      pred_existentes <- leer_dataset_si_existe(path_predicciones)
      escribir_dataset_reemplazo(
        pred_existentes,
        file.path(path_staging, "predicciones_operativas_cluster_dia"),
        partitioning = c("modelo_id", "version_modelo", "anio_mes")
      )
    }
    if (dir.exists(path_control)) {
      control_existente <- leer_dataset_si_existe(path_control)
      escribir_dataset_reemplazo(
        control_existente,
        file.path(path_staging, "control_scoring"),
        partitioning = c("modelo_id", "version_modelo")
      )
    }
    escribir_dataset_reemplazo(
      estado_inicial,
      file.path(path_staging, "estado_historico_final"),
      partitioning = c("version_cluster", "fecha_estado")
    )
  }

  ################################
  ### Cierro observados con COM y recalculo metricas
  path_pred_staging <- file.path(
    path_staging,
    "predicciones_operativas_cluster_dia"
  )
  predicciones_staging <- leer_dataset_si_existe(path_pred_staging)
  if (!is.null(predicciones_staging) && nrow(predicciones_staging) > 0L) {
    validar_columnas(
      predicciones_staging,
      c(
        "cluster_id",
        "dia_objetivo",
        "modelo_id",
        "version_modelo",
        "anio_mes"
      ),
      "predicciones staging"
    )
    validar_columnas(
      asignaciones_com,
      c("id", "dia", "cluster_id", "estado_asignacion_com"),
      "reclamos para cierre de observados"
    )
    message("Postproceso: preparando observados")
    predicciones_staging[, dia_objetivo := data.table::as.IDate(dia_objetivo)]
    observados <- construir_observados_operativos(
      predicciones_staging,
      asignaciones_com,
      fecha_com_cerrada_hasta
    )
    message(
      "Postproceso: observados construidos, filas=",
      nrow(observados),
      ", columnas=",
      paste(names(observados), collapse = ",")
    )
    if (nrow(observados) > 0L) {
      predicciones_staging <- actualizar_observados_operativos(
        predicciones_staging,
        observados,
        fecha_com_cerrada_hasta,
        target_col = "tuvo_reclamo"
      )
    }
    message("Postproceso: observados aplicados")
    escribir_dataset_reemplazo(
      predicciones_staging,
      path_pred_staging,
      partitioning = c("modelo_id", "version_modelo", "anio_mes")
    )

    metricas <- calcular_metricas_diarias_operativas(predicciones_staging)
    message("Postproceso: metricas calculadas, filas=", nrow(metricas))
    if (nrow(metricas) > 0L) {
      escribir_dataset_reemplazo(
        metricas,
        file.path(path_staging, "metricas_diarias"),
        partitioning = c("modelo_id", "version_modelo")
      )
    }
  }

  estado_final <- leer_dataset_si_existe(
    file.path(path_staging, "estado_historico_final")
  )
  message("Postproceso: estado final cargado")
  fecha_estado_final <- leer_fecha_unica_estado(estado_final)
  if (plan$requiere_scoring && fecha_estado_final != fecha_objetivo_hasta) {
    stop("El estado staging no llego a la fecha objetivo")
  }

  ################################
  ### Publicacion. El estado se publica ultimo y actua como commit.
  publicaciones <- list(
    c("predicciones_operativas_cluster_dia", "predicciones_operativas_cluster_dia"),
    c("control_scoring", "control_scoring"),
    c("metricas_diarias", "metricas_diarias")
  )
  for (pub in publicaciones) {
    publicar_directorio_transaccional(
      file.path(path_staging, pub[[1]]),
      file.path(out_base, pub[[2]]),
      file.path(path_backup, pub[[2]])
    )
  }
  publicar_directorio_transaccional(
    file.path(path_staging, "estado_historico_final"),
    path_estado,
    file.path(path_backup, "estado_historico_cluster")
  )

  control_ok <- preflight[, `:=`(
    timestamp_fin = Sys.time(),
    estado_ejecucion = if (plan$requiere_scoring) "completada" else "sin_dias_nuevos",
    mensaje = if (plan$requiere_scoring) {
      paste0("Procesados ", plan$dias_pendientes, " dias")
    } else {
      "No se recalcularon predicciones; se actualizaron observados disponibles"
    },
    fecha_estado_final = fecha_estado_final
  )]
  guardar_control_ejecucion(control_ok)
  print(control_ok)
  invisible(control_ok)
}, error = function(e) {
  registro_error <- data.table(
    run_id = run_id,
    timestamp_inicio = timestamp_inicio,
    timestamp_fin = Sys.time(),
    fecha_objetivo_hasta = fecha_objetivo_hasta,
    estado_ejecucion = "fallida",
    mensaje = conditionMessage(e),
    modelo_id = modelo_id,
    version_modelo = version_modelo
  )
  try(guardar_control_ejecucion(registro_error), silent = TRUE)
  stop(e)
})

invisible(resultado)
}

ejecutar_proceso()
