library(arrow)
library(data.table)
library(xgboost)

source("funciones/modelos_utils.R")
source("funciones/scoring_operativo_utils.R")

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L || is.na(x)) y else x
}

path_features <- Sys.getenv(
  "PATH_FEATURES",
  unset = "data/processed/modelo_cluster_dia/features_cluster_dia"
)
path_comparacion_zl <- Sys.getenv(
  "PATH_COMPARACION_ZL",
  unset = "data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia"
)
path_cluster_segmento <- Sys.getenv(
  "PATH_CLUSTER_SEGMENTO",
  unset = "data/processed/cluster_territorial/cluster_segmento_censal"
)
path_modelo_com <- Sys.getenv(
  "PATH_MODELO_COM",
  unset = "data/processed/modelos/logistico_cluster_dia_reducido_reclamos_d2/modelo_logistico_reducido.rds"
)
path_modelo_zl <- Sys.getenv(
  "PATH_MODELO_ZL",
  unset = "data/processed/modelos/experimentos_cascada_zl/operativo_segmento/modelo_zl_xgboost.rds"
)
path_feriados <- Sys.getenv(
  "PATH_FERIADOS",
  unset = "data/reference/feriados/feriados.R"
)
out_base <- Sys.getenv("OUT_BASE_APP", unset = "app_operativa_v2/data/operacional")

version_cluster_param <- Sys.getenv("VERSION_CLUSTER", unset = "")
fecha_desde_param <- Sys.getenv("FECHA_DESDE_APP", unset = "")
fecha_hasta_param <- Sys.getenv("FECHA_HASTA_APP", unset = "")
dias_validacion_app <- as.integer(Sys.getenv("DIAS_VALIDACION_APP", unset = "2"))
escenario_zl <- Sys.getenv("ESCENARIO_ZL_APP", unset = "random_dia_estratificado_mes")

modelo_id_com <- Sys.getenv("MODELO_ID_COM", unset = "com_reclamo")
modelo_id_zl <- Sys.getenv("MODELO_ID_ZL", unset = "zl_problema")
version_modelo_com_param <- Sys.getenv("VERSION_MODELO_COM", unset = "")
version_modelo_zl <- Sys.getenv(
  "VERSION_MODELO_ZL",
  unset = paste0("xgboost_operativo_segmento_", escenario_zl)
)

timestamp_ejecucion <- Sys.time()

normalizar_nivel <- function(x) {
  x <- as.character(x)
  x[is.na(x) | !nzchar(x)] <- "NA"
  x
}

nombre_seguro <- function(x) {
  x <- gsub("[^A-Za-z0-9_]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  data.table::fifelse(nzchar(x), x, "NA")
}

cargar_feriados <- function(path) {
  if (!file.exists(path)) {
    warning("No existe archivo de feriados: ", path)
    return(as.IDate(character()))
  }

  env <- new.env(parent = baseenv())
  sys.source(path, envir = env)

  if (!exists("diasDesc", envir = env, inherits = FALSE)) {
    warning("El archivo de feriados no define diasDesc: ", path)
    return(as.IDate(character()))
  }

  feriados <- get("diasDesc", envir = env, inherits = FALSE)
  if (is.data.frame(feriados) && "fecha" %in% names(feriados)) {
    return(as.IDate(feriados$fecha))
  }
  as.IDate(feriados)
}

preparar_matriz_xgb_app <- function(dt,
                                    features_numericas,
                                    features_categoricas,
                                    prep) {
  faltantes <- setdiff(c(features_numericas, features_categoricas), names(dt))
  if (length(faltantes) > 0L) {
    stop("Faltan features para ZL: ", paste(faltantes, collapse = ", "))
  }

  matrices <- list()
  for (col in features_numericas) {
    vals <- dt[[col]]
    if (is.logical(vals)) vals <- as.integer(vals)
    vals <- as.numeric(vals)
    vals[is.na(vals)] <- prep$medianas[[col]]
    matrices[[col]] <- vals
  }

  for (col in features_categoricas) {
    vals <- normalizar_nivel(dt[[col]])
    niveles <- prep$niveles[[col]]
    if (is.null(niveles)) niveles <- sort(unique(vals))
    for (nivel in niveles) {
      nombre_col <- paste0(col, "__", nombre_seguro(nivel))
      matrices[[nombre_col]] <- as.numeric(vals == nivel)
    }
  }

  as.matrix(as.data.table(matrices))
}

agregar_features_zl_app <- function(features, cluster_segmento, feriados) {
  datos <- cluster_segmento[
    features,
    on = c("version_cluster", "cluster_id")
  ]

  datos[, dia := as.IDate(dia)]
  datos[, dia_semana := as.integer(strftime(as.Date(dia), "%u"))]
  datos[, fin_de_semana := dia_semana %in% c(6L, 7L)]
  datos[, es_feriado := dia %in% feriados]
  datos[, vispera_feriado := (dia + 1L) %in% feriados]
  datos[, dia_habil := !fin_de_semana & !es_feriado]
  datos[, exceso_min_tiempo_periodo_pred_pos := pmax(min_tiempo_desde_ultimo_levante_pred - min_levante_periodo, 0)]
  datos[, exceso_mean_tiempo_periodo_pred_pos := pmax(mean_tiempo_desde_ultimo_levante_pred - mean_levante_periodo, 0)]
  datos[, exceso_max_tiempo_periodo_pred_pos := pmax(max_tiempo_desde_ultimo_levante_pred - max_levante_periodo, 0)]
  datos[, exceso_min_tiempo_periodo_pred_trunc7 := pmin(exceso_min_tiempo_periodo_pred_pos, 7)]
  datos[, exceso_mean_tiempo_periodo_pred_trunc7 := pmin(exceso_mean_tiempo_periodo_pred_pos, 7)]
  datos[, exceso_max_tiempo_periodo_pred_trunc7 := pmin(exceso_max_tiempo_periodo_pred_pos, 7)]

  datos
}

predecir_com <- function(features, modelo_com, version_cluster) {
  rezago <- as.integer(modelo_com$rezago_reclamos_dias %||% 1L)
  scoring <- aplicar_rezago_historia_reclamos(
    features,
    rezago_reclamos_dias = rezago
  )
  scoring <- agregar_features_logistico_reducido(scoring)

  version_modelo <- version_modelo_com_param
  if (!nzchar(version_modelo)) {
    version_modelo <- paste0("logistico_reducido_d", rezago)
  }

  pred <- generar_predicciones_logistico_operativo(
    scoring = scoring,
    modelo = modelo_com,
    timestamp_corte_features = timestamp_ejecucion,
    timestamp_ejecucion = timestamp_ejecucion,
    modelo_id = modelo_id_com,
    version_modelo = version_modelo,
    version_cluster = version_cluster,
    fecha_reclamos_usada_hasta = max(scoring$dia, na.rm = TRUE),
    timestamp_max_levante = as.POSIXct(NA),
    timestamp_max_com = as.POSIXct(NA)
  )

  observados <- scoring[
    ,
    .(
      cluster_id,
      dia_objetivo = dia,
      tuvo_reclamo_observado_new = as.integer(tuvo_reclamo),
      n_reclamos_observado_new = as.integer(n_reclamos)
    )
  ]
  pred <- observados[pred, on = c("cluster_id", "dia_objetivo")]
  pred[, `:=`(
    tuvo_reclamo_observado = tuvo_reclamo_observado_new,
    n_reclamos_observado = n_reclamos_observado_new,
    estado_observacion = "cerrado"
  )]
  pred[, c("tuvo_reclamo_observado_new", "n_reclamos_observado_new") := NULL]

  pred[, `:=`(
    target_app = "reclamo_com",
    target_app_label = "Reclamo COM",
    fuente_observado_modelo = "COM",
    problema_zl_observado = as.integer(NA),
    hay_zl_visita_efectiva = as.integer(NA),
    n_zl_problema_comparable = as.integer(NA),
    estado_observacion_zl = "no_aplica"
  )]

  pred
}

predecir_zl <- function(features,
                        comparacion_zl,
                        cluster_segmento,
                        feriados,
                        modelo_zl,
                        version_cluster) {
  if (!escenario_zl %in% names(modelo_zl)) {
    stop("No existe el escenario ZL en el RDS: ", escenario_zl)
  }

  fit <- xgboost::xgb.Booster.complete(modelo_zl[[escenario_zl]]$fit)
  prep <- modelo_zl[[escenario_zl]]$prep
  datos_zl <- agregar_features_zl_app(features, cluster_segmento, feriados)

  mat <- preparar_matriz_xgb_app(
    datos_zl,
    features_numericas = modelo_zl$features_numericas,
    features_categoricas = modelo_zl$features_categoricas,
    prep = prep
  )
  pred_prob <- as.numeric(stats::predict(fit, mat))

  observados_zl <- comparacion_zl[
    ,
    .(
      cluster_id,
      dia_objetivo = dia,
      hay_zl_visita_efectiva = as.integer(hay_zl_visita_efectiva),
      problema_zl_observado = as.integer(hay_zl_problema_comparable),
      n_zl_problema_comparable = as.integer(n_zl_problema_comparable)
    )
  ]

  cols_resumen <- intersect(
    c(
      "n_reclamos_lag1",
      "n_reclamos_sum_7d",
      "n_reclamos_sum_30d",
      "dias_desde_ultimo_reclamo_o_inicio_trunc_90",
      "mean_tiempo_desde_ultimo_levante_pred",
      "n_contenedores_activos",
      "pct_contenedores_inferidos"
    ),
    names(datos_zl)
  )

  pred <- datos_zl[, c(
    list(
      cluster_id = cluster_id,
      dia_objetivo = dia,
      anio_mes = anio_mes,
      modelo_id = modelo_id_zl,
      version_modelo = version_modelo_zl,
      version_cluster = version_cluster,
      timestamp_corte_features = timestamp_ejecucion,
      timestamp_ejecucion = timestamp_ejecucion,
      pred_prob = pred_prob,
      fecha_reclamos_usada_hasta = max(dia, na.rm = TRUE),
      timestamp_max_levante = as.POSIXct(NA),
      timestamp_max_com = as.POSIXct(NA),
      estado_prediccion = "generada",
      tuvo_reclamo_observado = as.integer(tuvo_reclamo),
      n_reclamos_observado = as.integer(n_reclamos),
      estado_observacion = "cerrado",
      target_app = "problema_zl",
      target_app_label = "Problema observado ZL",
      fuente_observado_modelo = "Zona Limpia"
    ),
    .SD
  ), .SDcols = cols_resumen]

  pred <- observados_zl[pred, on = c("cluster_id", "dia_objetivo")]
  pred[is.na(hay_zl_visita_efectiva), hay_zl_visita_efectiva := 0L]
  pred[
    hay_zl_visita_efectiva != 1L,
    `:=`(
      problema_zl_observado = as.integer(NA),
      n_zl_problema_comparable = as.integer(NA),
      estado_observacion_zl = "no_observado"
    )
  ]
  pred[
    hay_zl_visita_efectiva == 1L,
    estado_observacion_zl := "observado"
  ]

  agregar_ranking_operativo(pred)
}

if (!dir.exists(path_features)) stop("No existe path_features: ", path_features)
if (!dir.exists(path_comparacion_zl)) stop("No existe path_comparacion_zl: ", path_comparacion_zl)
if (!dir.exists(path_cluster_segmento)) stop("No existe path_cluster_segmento: ", path_cluster_segmento)
if (!file.exists(path_modelo_com)) stop("No existe path_modelo_com: ", path_modelo_com)
if (!file.exists(path_modelo_zl)) stop("No existe path_modelo_zl: ", path_modelo_zl)

features <- as.data.table(as.data.frame(arrow::open_dataset(path_features, format = "parquet")))
features[, dia := as.IDate(dia)]
features <- features[cluster_existente_dia == TRUE]

if (nzchar(version_cluster_param)) {
  features <- features[version_cluster == version_cluster_param]
}
version_cluster_obj <- sort(unique(features$version_cluster))
version_cluster_obj <- version_cluster_obj[length(version_cluster_obj)]
features <- features[version_cluster == version_cluster_obj]

if (nzchar(fecha_desde_param)) {
  features <- features[dia >= as.IDate(fecha_desde_param)]
}
if (nzchar(fecha_hasta_param)) {
  features <- features[dia <= as.IDate(fecha_hasta_param)]
}
if (nrow(features) == 0L) {
  stop("No hay features para construir la salida de app")
}

fecha_max <- max(features$dia, na.rm = TRUE)
fecha_cierre <- fecha_max - dias_validacion_app

modelo_com <- readRDS(path_modelo_com)
modelo_zl <- readRDS(path_modelo_zl)
cluster_segmento <- as.data.table(as.data.frame(arrow::open_dataset(path_cluster_segmento, format = "parquet")))
cluster_segmento <- cluster_segmento[version_cluster == version_cluster_obj]
comparacion_zl <- as.data.table(as.data.frame(arrow::open_dataset(path_comparacion_zl, format = "parquet")))
comparacion_zl[, dia := as.IDate(dia)]
comparacion_zl <- comparacion_zl[version_cluster == version_cluster_obj]
feriados <- cargar_feriados(path_feriados)

pred_com <- predecir_com(features, modelo_com, version_cluster_obj)
pred_zl <- predecir_zl(
  features = features,
  comparacion_zl = comparacion_zl,
  cluster_segmento = cluster_segmento,
  feriados = feriados,
  modelo_zl = modelo_zl,
  version_cluster = version_cluster_obj
)

predicciones <- rbindlist(list(pred_com, pred_zl), fill = TRUE)
predicciones[, estado_periodo_app := data.table::fifelse(
  dia_objetivo > fecha_cierre,
  "validacion_actualizacion",
  "historico_cerrado"
)]
predicciones[
  dia_objetivo > fecha_cierre,
  estado_observacion := "pendiente_validacion"
]

predicciones <- rbindlist(
  lapply(
    split(predicciones, by = c("modelo_id", "version_modelo", "dia_objetivo"), keep.by = TRUE),
    agregar_ranking_operativo
  ),
  fill = TRUE
)

control <- predicciones[
  ,
  .(
    estado_prediccion = "generada",
    n_predicciones = .N,
    timestamp_ejecucion = max(timestamp_ejecucion),
    estado_periodo_app = unique(estado_periodo_app)
  ),
  by = .(dia_objetivo, modelo_id, version_modelo)
]

metricas <- calcular_metricas_diarias_operativas(predicciones[modelo_id == modelo_id_com])
if (nrow(metricas) > 0L) {
  metricas[, target_app := "reclamo_com"]
}

dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
escribir_dataset_reemplazo(
  predicciones,
  file.path(out_base, "predicciones_operativas_cluster_dia"),
  partitioning = c("modelo_id", "version_modelo", "anio_mes")
)
escribir_dataset_reemplazo(
  control,
  file.path(out_base, "control_scoring"),
  partitioning = c("modelo_id", "version_modelo")
)
if (nrow(metricas) > 0L) {
  escribir_dataset_reemplazo(
    metricas,
    file.path(out_base, "metricas_diarias"),
    partitioning = c("modelo_id", "version_modelo")
  )
}

resumen <- predicciones[
  ,
  .(
    dias = uniqueN(dia_objetivo),
    filas = .N,
    score_min = min(pred_prob, na.rm = TRUE),
    score_p50 = median(pred_prob, na.rm = TRUE),
    score_max = max(pred_prob, na.rm = TRUE),
    desde = min(dia_objetivo),
    hasta = max(dia_objetivo)
  ),
  by = .(modelo_id, version_modelo, target_app)
]
fwrite(resumen, file.path(out_base, "resumen_modelos_largo.csv"))

print(resumen)
