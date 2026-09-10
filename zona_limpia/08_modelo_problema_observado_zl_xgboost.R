library(arrow)
library(data.table)
library(xgboost)

source("funciones/modelos_utils.R")

path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_comparacion_zl <- "data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia"
path_cluster_segmento <- "data/processed/cluster_territorial/cluster_segmento_censal"
path_cluster_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
path_feriados <- "data/reference/feriados/feriados.R"
path_clima_features <- "data/processed/clima/inumet_melilla_g3/clima_inumet_melilla_g3_features_diarias.csv"
out_base <- Sys.getenv(
  "OUT_BASE_MODELO_ZL",
  unset = "data/processed/modelos/zona_limpia_problema_observado_xgboost"
)
out_outputs <- Sys.getenv("OUT_OUTPUTS_MODELO_ZL", unset = "zona_limpia/outputs")

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
meses_modelo <- as.integer(strsplit(
  Sys.getenv("MESES_MODELO_ZL", unset = "202510,202511,202512,202603,202604,202605"),
  ","
)[[1]])
meses_train_temporal <- as.integer(strsplit(
  Sys.getenv("MESES_TRAIN_TEMPORAL_ZL", unset = "202510,202511,202512"),
  ","
)[[1]])
meses_valid_temporal <- as.integer(strsplit(
  Sys.getenv("MESES_VALID_TEMPORAL_ZL", unset = "202603"),
  ","
)[[1]])
meses_test_temporal <- as.integer(strsplit(
  Sys.getenv("MESES_TEST_TEMPORAL_ZL", unset = "202604,202605"),
  ","
)[[1]])
n_reps_random_dia <- as.integer(Sys.getenv("N_REPS_RANDOM_DIA_ZL", unset = "5"))
semilla_random_dia <- as.integer(Sys.getenv("SEMILLA_RANDOM_DIA_ZL", unset = "20260703"))
feature_set_zl <- Sys.getenv("FEATURE_SET_ZL", unset = "amplio_actual")
usar_clima <- Sys.getenv("USAR_CLIMA", unset = "0") %in% c("1", "TRUE", "true", "SI", "si")
usar_clima <- usar_clima || feature_set_zl %in% c("operativo_clima", "segmento_clima", "amplio_actual_clima")

set.seed(20260703)

dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
dir.create(out_outputs, recursive = TRUE, showWarnings = FALSE)

xgb_nrounds <- as.integer(Sys.getenv("NROUNDS_XGB_ZL", unset = "250"))
xgb_params <- list(
  objective = "binary:logistic",
  eval_metric = "logloss",
  max_depth = 4L,
  eta = 0.05,
  subsample = 0.85,
  colsample_bytree = 0.85,
  min_child_weight = 25,
  nthread = 4L
)

features_contenedores <- c(
  "n_contenedores_activos",
  "n_contenedores_elegibles_modelo",
  "n_contenedores_observados",
  "n_contenedores_inferidos",
  "pct_contenedores_inferidos",
  "pct_contenedores_elegibles_modelo"
)

features_levante <- c(
  "min_tiempo_desde_ultimo_levante_pred",
  "mean_tiempo_desde_ultimo_levante_pred",
  "median_tiempo_desde_ultimo_levante_pred",
  "max_tiempo_desde_ultimo_levante_pred",
  "min_ratio_tiempo_periodo_pred",
  "mean_ratio_tiempo_periodo_pred",
  "median_ratio_tiempo_periodo_pred",
  "max_ratio_tiempo_periodo_pred",
  "min_levante_periodo",
  "mean_levante_periodo",
  "max_levante_periodo",
  "exceso_min_tiempo_periodo_pred_pos",
  "exceso_mean_tiempo_periodo_pred_pos",
  "exceso_max_tiempo_periodo_pred_pos",
  "exceso_min_tiempo_periodo_pred_trunc7",
  "exceso_mean_tiempo_periodo_pred_trunc7",
  "exceso_max_tiempo_periodo_pred_trunc7",
  "mean_dias_total_tramo_inferido_estado",
  "max_dias_total_tramo_inferido_estado"
)

features_calendario_operativo <- c(
  "dia_semana",
  "fin_de_semana",
  "es_feriado",
  "vispera_feriado",
  "dia_habil"
)

features_calendario_amplio <- c(
  "mes_calendario",
  features_calendario_operativo
)

features_segmento_parsimonioso <- c(
  "porc_nbi_segmento",
  "porc_asentamiento_nbi_segmento",
  "porc_vivienda_inadecuada_segmento",
  "densidad_pob_km2",
  "cluster_multisegmento",
  "pct_posiciones_segmento_principal"
)

features_segmento_amplio <- c(
  "poblacion_segmento",
  "hogares_segmento",
  "viviendas_segmento",
  "viviendas_ocupadas_segmento",
  features_segmento_parsimonioso,
  "densidad_hog_km2",
  "densidad_viv_km2",
  "n_segmentos_posiciones"
)

features_agregados_territoriales <- c(
  "poblacion_ccz_2023",
  "viviendas_ccz_2023",
  "densidad_pob_ccz_2023_km2",
  "densidad_viv_ccz_2023_km2",
  "poblacion_barrio_2023",
  "viviendas_barrio_2023",
  "densidad_pob_barrio_2023_km2",
  "densidad_viv_barrio_2023_km2"
)

features_clima <- c(
  "precipitacion_d1_mm",
  "precipitacion_max_hora_d1_mm",
  "horas_con_lluvia_d1",
  "llovio_d1",
  "precipitacion_3d_mm",
  "precipitacion_max_hora_3d_mm",
  "dias_con_lluvia_3d",
  "temp_media_d1_c",
  "temp_min_d1_c",
  "temp_max_d1_c",
  "temp_rango_d1_c",
  "temp_media_3d_c",
  "temp_min_3d_c",
  "temp_max_3d_c",
  "horas_temp_validas_d1",
  "horas_prec_validas_d1",
  "horas_temp_validas_3d",
  "horas_prec_validas_3d"
)

features_numericas_amplio <- c(
  features_contenedores,
  features_levante,
  features_segmento_amplio,
  features_agregados_territoriales,
  features_calendario_amplio
)

feature_sets <- list(
  operativo_minimo = list(
    numericas = c(features_contenedores, features_levante, features_calendario_operativo),
    categoricas = character()
  ),
  operativo_segmento = list(
    numericas = c(features_contenedores, features_levante, features_segmento_parsimonioso, features_calendario_operativo),
    categoricas = character()
  ),
  operativo_clima = list(
    numericas = c(features_contenedores, features_levante, features_calendario_operativo, features_clima),
    categoricas = character()
  ),
  segmento_clima = list(
    numericas = c(features_contenedores, features_levante, features_segmento_parsimonioso, features_calendario_operativo, features_clima),
    categoricas = character()
  ),
  amplio_actual = list(
    numericas = features_numericas_amplio,
    categoricas = c("municipio", "ccz", "nombre_barrio_ine")
  ),
  amplio_actual_clima = list(
    numericas = c(features_numericas_amplio, features_clima),
    categoricas = c("municipio", "ccz", "nombre_barrio_ine")
  )
)

if (!feature_set_zl %in% names(feature_sets)) {
  stop("FEATURE_SET_ZL invalido. Opciones: ", paste(names(feature_sets), collapse = ", "))
}

features_numericas <- unique(feature_sets[[feature_set_zl]]$numericas)
features_categoricas <- unique(feature_sets[[feature_set_zl]]$categoricas)

normalizar_nivel <- function(x) {
  x <- toupper(trimws(as.character(x)))
  x[is.na(x) | x == ""] <- "SIN_DATO"
  iconv(x, from = "", to = "ASCII//TRANSLIT")
}

nombre_seguro <- function(x) {
  make.names(gsub("[^A-Za-z0-9_]+", "_", x), unique = TRUE)
}

cargar_feriados <- function(path) {
  if (!file.exists(path)) {
    warning("No existe archivo de feriados: ", path)
    return(as.IDate(character()))
  }

  env <- new.env(parent = baseenv())
  sys.source(path, envir = env)

  if (!exists("diasDesc", envir = env)) {
    warning("El archivo de feriados no define diasDesc: ", path)
    return(as.IDate(character()))
  }

  unique(as.IDate(get("diasDesc", envir = env)))
}

crear_split_random_dia <- function(datos, semilla) {
  set.seed(semilla)
  dias_split <- unique(datos[, .(anio_mes, dia)])
  dias_split[, random_u_dia := runif(.N)]
  dias_split[
    ,
    random_rank_dia := frank(random_u_dia, ties.method = "random") / .N,
    by = anio_mes
  ]
  dias_split[, split_random_dia := fcase(
    random_rank_dia <= 0.70, "train",
    random_rank_dia <= 0.85, "validacion",
    default = "test"
  )]
  dias_split[, c("random_u_dia", "random_rank_dia") := NULL]
  dias_split[]
}

preparar_matriz_xgb <- function(dt,
                                features_numericas,
                                features_categoricas,
                                prep = NULL) {
  x_num <- data.table::copy(dt[, ..features_numericas])

  for (col in names(x_num)) {
    if (is.logical(x_num[[col]])) x_num[, (col) := as.integer(get(col))]
    if (is.integer(x_num[[col]])) x_num[, (col) := as.numeric(get(col))]
  }

  if (is.null(prep)) {
    medianas <- lapply(features_numericas, function(col) {
      med <- stats::median(x_num[[col]], na.rm = TRUE)
      if (is.na(med) || is.infinite(med)) med <- 0
      med
    })
    names(medianas) <- features_numericas

    niveles <- lapply(features_categoricas, function(col) {
      sort(unique(c(normalizar_nivel(dt[[col]]), "OTRO", "SIN_DATO")))
    })
    names(niveles) <- features_categoricas

    prep <- list(medianas = medianas, niveles = niveles)
  }

  for (col in features_numericas) {
    x_num[is.na(get(col)) | is.infinite(get(col)), (col) := prep$medianas[[col]]]
  }

  mats <- list(as.matrix(x_num))
  for (col in features_categoricas) {
    vals <- normalizar_nivel(dt[[col]])
    niveles_col <- prep$niveles[[col]]
    vals[!vals %in% niveles_col] <- "OTRO"
    vals <- factor(vals, levels = niveles_col)
    mm <- stats::model.matrix(~ vals - 1)
    colnames(mm) <- paste0(col, "__", nombre_seguro(levels(vals)))
    mats[[length(mats) + 1L]] <- mm
  }

  x <- do.call(cbind, mats)
  storage.mode(x) <- "numeric"

  list(x = x, prep = prep)
}

evaluar_predicciones <- function(pred, escenario) {
  metricas <- pred[
    ,
    .(
      n = .N,
      positivos = sum(target_problema_observado),
      prevalencia = mean(target_problema_observado),
      auc = auc_binaria(target_problema_observado, pred_prob),
      logloss = logloss_binaria(target_problema_observado, pred_prob)
    ),
    by = split
  ]
  metricas[, escenario := escenario]

  lift <- pred[
    ,
    lift_top(
      data.table::copy(.SD),
      score_col = "pred_prob",
      y_col = "target_problema_observado",
      cortes = c(0.05, 0.10, 0.20, 0.30)
    ),
    by = split
  ]
  lift[, escenario := escenario]

  calibracion <- pred[
    ,
    calibracion_deciles(
      data.table::copy(.SD),
      score_col = "pred_prob",
      y_col = "target_problema_observado"
    ),
    by = split
  ]
  calibracion[, escenario := escenario]

  list(metricas = metricas, lift = lift, calibracion = calibracion)
}

evaluar_predicciones_target <- function(pred, y_col, escenario, target_eval) {
  metricas <- pred[
    ,
    {
      y <- get(y_col)
      auc <- if (data.table::uniqueN(y) == 2L) {
        auc_binaria(y, pred_prob)
      } else {
        NA_real_
      }
      ll <- if (data.table::uniqueN(y) == 2L) {
        logloss_binaria(y, pred_prob)
      } else {
        NA_real_
      }
      .(
        n = .N,
        positivos = sum(y),
        prevalencia = mean(y),
        auc = auc,
        logloss = ll
      )
    },
    by = split
  ]
  metricas[, `:=`(
    escenario = escenario,
    target_eval = target_eval
  )]

  metricas[]
}

entrenar_escenario <- function(datos, split_col, escenario) {
  train <- datos[get(split_col) == "train"]
  valid <- datos[get(split_col) == "validacion"]
  test <- datos[get(split_col) == "test"]

  if (nrow(train) == 0L || nrow(valid) == 0L || nrow(test) == 0L) {
    stop("El escenario ", escenario, " tiene train/validacion/test vacios.")
  }

  y_train <- train$target_problema_observado
  y_valid <- valid$target_problema_observado
  y_test <- test$target_problema_observado

  mat_train <- preparar_matriz_xgb(train, features_numericas, features_categoricas)
  mat_valid <- preparar_matriz_xgb(valid, features_numericas, features_categoricas, prep = mat_train$prep)
  mat_test <- preparar_matriz_xgb(test, features_numericas, features_categoricas, prep = mat_train$prep)

  dtrain <- xgboost::xgb.DMatrix(data = mat_train$x, label = y_train)
  dvalid <- xgboost::xgb.DMatrix(data = mat_valid$x, label = y_valid)
  dtest <- xgboost::xgb.DMatrix(data = mat_test$x, label = y_test)

  tiempo_entrenamiento <- system.time({
    fit <- xgboost::xgb.train(
      params = xgb_params,
      data = dtrain,
      nrounds = xgb_nrounds,
      watchlist = list(train = dtrain, validacion = dvalid),
      verbose = 0
    )
  })

  pred_train <- as.numeric(predict(fit, dtrain))
  pred_valid <- as.numeric(predict(fit, dvalid))
  pred_test <- as.numeric(predict(fit, dtest))

  predicciones <- rbindlist(list(
    train[, .(
      cluster_id,
      dia,
      anio_mes,
      split = "train",
      target_problema_observado,
      target_zl_problema_comparable,
      target_com,
      target_hibrido_com_o_zl,
      target_solo_zl_sin_com,
      hay_com,
      hay_zl_problema_comparable,
      municipio,
      ccz,
      nombre_barrio_ine,
      pred_prob = pred_train
    )],
    valid[, .(
      cluster_id,
      dia,
      anio_mes,
      split = "validacion",
      target_problema_observado,
      target_zl_problema_comparable,
      target_com,
      target_hibrido_com_o_zl,
      target_solo_zl_sin_com,
      hay_com,
      hay_zl_problema_comparable,
      municipio,
      ccz,
      nombre_barrio_ine,
      pred_prob = pred_valid
    )],
    test[, .(
      cluster_id,
      dia,
      anio_mes,
      split = "test",
      target_problema_observado,
      target_zl_problema_comparable,
      target_com,
      target_hibrido_com_o_zl,
      target_solo_zl_sin_com,
      hay_com,
      hay_zl_problema_comparable,
      municipio,
      ccz,
      nombre_barrio_ine,
      pred_prob = pred_test
    )]
  ), use.names = TRUE)

  predicciones[, escenario := escenario]
  predicciones[, version_cluster := target_version_cluster]

  evaluacion <- evaluar_predicciones(predicciones, escenario)

  importancia <- as.data.table(xgboost::xgb.importance(
    feature_names = colnames(mat_train$x),
    model = fit
  ))
  importancia[, escenario := escenario]

  parametros <- data.table(
    escenario = escenario,
    version_cluster = target_version_cluster,
    filas_train = nrow(train),
    filas_validacion = nrow(valid),
    filas_test = nrow(test),
    positivos_train = sum(y_train),
    positivos_validacion = sum(y_valid),
    positivos_test = sum(y_test),
    meses_train = paste(sort(unique(train$anio_mes)), collapse = ","),
    meses_validacion = paste(sort(unique(valid$anio_mes)), collapse = ","),
    meses_test = paste(sort(unique(test$anio_mes)), collapse = ","),
    feature_set_zl = feature_set_zl,
    features_numericas = length(features_numericas),
    features_categoricas = length(features_categoricas),
    features_clima = sum(features_numericas %in% features_clima),
    columnas_matriz = ncol(mat_train$x),
    nrounds = xgb_nrounds,
    max_depth = xgb_params$max_depth,
    eta = xgb_params$eta,
    subsample = xgb_params$subsample,
    colsample_bytree = xgb_params$colsample_bytree,
    min_child_weight = xgb_params$min_child_weight,
    usar_clima = usar_clima,
    segundos_entrenamiento = as.numeric(tiempo_entrenamiento[["elapsed"]])
  )

  list(
    fit = fit,
    prep = mat_train$prep,
    predicciones = predicciones,
    metricas = evaluacion$metricas,
    lift = evaluacion$lift,
    calibracion = evaluacion$calibracion,
    importancia = importancia,
    parametros = parametros
  )
}

if (!dir.exists(path_cluster_admin)) {
  stop("No existe cluster_admin_territorial. Ejecutar scripts/construir_cluster_territorial_admin.R")
}

features <- as.data.table(arrow::open_dataset(path_features, format = "parquet"))
comparacion_zl <- as.data.table(arrow::open_dataset(path_comparacion_zl, format = "parquet"))
cluster_segmento <- as.data.table(arrow::open_dataset(path_cluster_segmento, format = "parquet"))
cluster_admin <- as.data.table(arrow::open_dataset(path_cluster_admin, format = "parquet"))
feriados <- cargar_feriados(path_feriados)

if (usar_clima) {
  if (!file.exists(path_clima_features)) {
    stop("No existe tabla de features climaticas: ", path_clima_features)
  }
  clima_features <- data.table::fread(path_clima_features)
  clima_features[, dia := as.IDate(dia)]
  features[, dia := as.IDate(dia)]
  features <- clima_features[
    features,
    on = "dia"
  ]
}

if (is.na(target_version_cluster) || target_version_cluster == "") {
  versiones <- sort(unique(features$version_cluster))
  target_version_cluster <- versiones[length(versiones)]
}

for (dt in list(features, comparacion_zl, cluster_segmento, cluster_admin)) {
  dt[, version_cluster := as.character(version_cluster)]
  dt[, cluster_id := as.character(cluster_id)]
}

features <- features[version_cluster == target_version_cluster & anio_mes %in% meses_modelo]
comparacion_zl <- comparacion_zl[
  version_cluster == target_version_cluster &
    anio_mes %in% meses_modelo &
    hay_zl_visita_efectiva == TRUE &
    hay_zl_voluminosos != TRUE
]
cluster_segmento <- cluster_segmento[version_cluster == target_version_cluster]
cluster_admin <- cluster_admin[version_cluster == target_version_cluster]

datos <- comparacion_zl[
  ,
  .(
    cluster_id,
    dia = as.IDate(dia),
    anio_mes,
    hay_com,
    hay_zl_problema_comparable,
    hay_zl_limpio
  )
][
  features,
  on = .(cluster_id, dia, anio_mes),
  nomatch = 0
]

datos <- cluster_segmento[
  datos,
  on = c("version_cluster", "cluster_id")
]
datos <- cluster_admin[
  datos,
  on = c("version_cluster", "cluster_id")
]

datos[, target_zl_problema_comparable := as.integer(hay_zl_problema_comparable == TRUE)]
datos[, target_com := as.integer(hay_com == TRUE)]
datos[, target_hibrido_com_o_zl := as.integer(hay_com == TRUE | hay_zl_problema_comparable == TRUE)]
datos[, target_problema_observado := target_zl_problema_comparable]
datos[, target_solo_zl_sin_com := as.integer(hay_zl_problema_comparable == TRUE & hay_com != TRUE)]
datos[, mes_calendario := as.integer(format(as.IDate(dia), "%m"))]
datos[, dia_semana := as.integer(format(as.IDate(dia), "%u"))]
datos[, fin_de_semana := dia_semana %in% c(6L, 7L)]
datos[, es_feriado := as.IDate(dia) %in% feriados]
datos[, vispera_feriado := (as.IDate(dia) + 1L) %in% feriados]
datos[, dia_habil := !fin_de_semana & !es_feriado]
datos[, exceso_min_tiempo_periodo_pred_pos := pmax(min_tiempo_desde_ultimo_levante_pred - min_levante_periodo, 0)]
datos[, exceso_mean_tiempo_periodo_pred_pos := pmax(mean_tiempo_desde_ultimo_levante_pred - mean_levante_periodo, 0)]
datos[, exceso_max_tiempo_periodo_pred_pos := pmax(max_tiempo_desde_ultimo_levante_pred - max_levante_periodo, 0)]
datos[, exceso_min_tiempo_periodo_pred_trunc7 := pmin(exceso_min_tiempo_periodo_pred_pos, 7)]
datos[, exceso_mean_tiempo_periodo_pred_trunc7 := pmin(exceso_mean_tiempo_periodo_pred_pos, 7)]
datos[, exceso_max_tiempo_periodo_pred_trunc7 := pmin(exceso_max_tiempo_periodo_pred_pos, 7)]
datos[, ccz := as.character(ccz)]

faltantes_features <- setdiff(
  c(features_numericas, features_categoricas, "target_problema_observado"),
  names(datos)
)
if (length(faltantes_features) > 0L) {
  stop("Faltan columnas para modelo ZL: ", paste(faltantes_features, collapse = ", "))
}

datos <- datos[!is.na(target_problema_observado)]
datos[, split_temporal := fcase(
  anio_mes %in% meses_train_temporal, "train",
  anio_mes %in% meses_valid_temporal, "validacion",
  anio_mes %in% meses_test_temporal, "test",
  default = NA_character_
)]
datos <- datos[!is.na(split_temporal)]

datos[, random_u := runif(.N)]
datos[
  ,
  random_rank := frank(random_u, ties.method = "random") / .N,
  by = .(anio_mes, target_problema_observado)
]
datos[, split_random := fcase(
  random_rank <= 0.70, "train",
  random_rank <= 0.85, "validacion",
  default = "test"
)]
datos[, c("random_u", "random_rank") := NULL]

dias_split <- crear_split_random_dia(datos, semilla_random_dia)

datos <- dias_split[
  datos,
  on = .(anio_mes, dia)
]

resumen_base <- datos[
  ,
  .(
    filas = .N,
    positivos = sum(target_problema_observado),
    prevalencia = mean(target_problema_observado),
    clusters = uniqueN(cluster_id),
    dias = uniqueN(dia)
  ),
  by = anio_mes
][order(anio_mes)]

resumen_splits_temporal <- datos[
  ,
  .(
    filas = .N,
    positivos = sum(target_problema_observado),
    prevalencia = mean(target_problema_observado),
    clusters = uniqueN(cluster_id),
    dias = uniqueN(dia)
  ),
  by = .(split = split_temporal)
]
resumen_splits_temporal[, escenario := "temporal"]

resumen_splits_random <- datos[
  ,
  .(
    filas = .N,
    positivos = sum(target_problema_observado),
    prevalencia = mean(target_problema_observado),
    clusters = uniqueN(cluster_id),
    dias = uniqueN(dia)
  ),
  by = .(split = split_random)
]
resumen_splits_random[, escenario := "random_estratificado_mes"]

resumen_splits_random_dia <- datos[
  ,
  .(
    filas = .N,
    positivos = sum(target_problema_observado),
    prevalencia = mean(target_problema_observado),
    clusters = uniqueN(cluster_id),
    dias = uniqueN(dia)
  ),
  by = .(split = split_random_dia)
]
resumen_splits_random_dia[, escenario := "random_dia_estratificado_mes"]

resumen_splits <- rbindlist(list(
  resumen_splits_temporal,
  resumen_splits_random,
  resumen_splits_random_dia
), use.names = TRUE)[order(escenario, split)]

resultado_temporal <- entrenar_escenario(datos, "split_temporal", "temporal")
resultado_random <- entrenar_escenario(datos, "split_random", "random_estratificado_mes")
resultado_random_dia <- entrenar_escenario(datos, "split_random_dia", "random_dia_estratificado_mes")

resultados_random_dia_reps <- vector("list", n_reps_random_dia)
resumen_random_dia_reps <- vector("list", n_reps_random_dia)

if (n_reps_random_dia > 0L) {
  for (i in seq_len(n_reps_random_dia)) {
    semilla_rep <- semilla_random_dia + i
    datos_rep <- data.table::copy(datos)
    datos_rep[, split_random_dia := NULL]
    split_rep <- crear_split_random_dia(datos_rep, semilla_rep)
    datos_rep <- split_rep[
      datos_rep,
      on = .(anio_mes, dia)
    ]

    resumen_rep <- datos_rep[
      ,
      .(
        filas = .N,
        positivos = sum(target_problema_observado),
        prevalencia = mean(target_problema_observado),
        clusters = uniqueN(cluster_id),
        dias = uniqueN(dia)
      ),
      by = .(split = split_random_dia)
    ]
    resumen_rep[, `:=`(
      rep = i,
      semilla = semilla_rep,
      escenario = "random_dia_repetido"
    )]
    resumen_random_dia_reps[[i]] <- resumen_rep

    resultado_rep <- entrenar_escenario(
      datos_rep,
      "split_random_dia",
      "random_dia_repetido"
    )
    metricas_rep <- resultado_rep$metricas
    metricas_rep[, `:=`(
      rep = i,
      semilla = semilla_rep
    )]
    resultados_random_dia_reps[[i]] <- metricas_rep
  }
}

metricas_random_dia_reps <- rbindlist(resultados_random_dia_reps, use.names = TRUE, fill = TRUE)
resumen_random_dia_reps <- rbindlist(resumen_random_dia_reps, use.names = TRUE, fill = TRUE)

predicciones <- rbindlist(list(
  resultado_temporal$predicciones,
  resultado_random$predicciones,
  resultado_random_dia$predicciones
), use.names = TRUE, fill = TRUE)
metricas <- rbindlist(list(resultado_temporal$metricas, resultado_random$metricas, resultado_random_dia$metricas), fill = TRUE)
lift <- rbindlist(list(resultado_temporal$lift, resultado_random$lift, resultado_random_dia$lift), fill = TRUE)
calibracion <- rbindlist(list(resultado_temporal$calibracion, resultado_random$calibracion, resultado_random_dia$calibracion), fill = TRUE)
importancia <- rbindlist(list(resultado_temporal$importancia, resultado_random$importancia, resultado_random_dia$importancia), fill = TRUE)
parametros <- rbindlist(list(resultado_temporal$parametros, resultado_random$parametros, resultado_random_dia$parametros), fill = TRUE)

features_matriz <- unique(c(
  names(resultado_temporal$prep$medianas),
  importancia$Feature
))
if (length(features_matriz) == 0L) {
  features_matriz <- importancia$Feature
}
inventario_features <- CJ(
  escenario = unique(importancia$escenario),
  feature = unique(c(features_matriz, importancia$Feature))
)
inventario_features[, `:=`(
  modelo = "xgboost_zl",
  variante = feature_set_zl,
  familia = fcase(
    feature %in% features_clima, "clima",
    grepl("municipio|ccz|barrio|segmento|poblacion|vivienda|hogar|densidad|nbi", feature), "territorio",
    grepl("levante|tiempo|periodo|tramo|exceso|ratio", feature), "levante",
    grepl("contenedor|inferido|elegible", feature), "contenedores",
    grepl("feriado|dia_|semana|mes|fin_de_semana", feature), "calendario",
    default = "otra"
  )
)]
inventario_features <- importancia[
  inventario_features,
  on = c("escenario", Feature = "feature")
]
setnames(inventario_features, "Feature", "feature")
inventario_features[is.na(Gain), `:=`(Gain = 0, Cover = 0, Frequency = 0)]

targets_eval <- list(
  target_principal = "target_problema_observado",
  target_hibrido_com_o_zl = "target_hibrido_com_o_zl",
  target_com = "target_com",
  target_solo_zl_sin_com = "target_solo_zl_sin_com"
)

predicciones_por_escenario <- split(predicciones, by = "escenario", keep.by = TRUE)
metricas_targets <- rbindlist(lapply(names(targets_eval), function(target_eval) {
  y_col <- targets_eval[[target_eval]]
  rbindlist(lapply(predicciones_por_escenario, function(dt_pred) {
    evaluar_predicciones_target(
      dt_pred,
      y_col = y_col,
      escenario = unique(dt_pred$escenario),
      target_eval = target_eval
    )
  }), use.names = TRUE)
}), use.names = TRUE, fill = TRUE)

metricas[, version_cluster := target_version_cluster]
lift[, version_cluster := target_version_cluster]
calibracion[, version_cluster := target_version_cluster]
importancia[, version_cluster := target_version_cluster]
inventario_features[, version_cluster := target_version_cluster]
metricas_targets[, version_cluster := target_version_cluster]
if (nrow(metricas_random_dia_reps) > 0L) {
  metricas_random_dia_reps[, version_cluster := target_version_cluster]
}
if (nrow(resumen_random_dia_reps) > 0L) {
  resumen_random_dia_reps[, version_cluster := target_version_cluster]
}

parametros[, meses_modelo := paste(meses_modelo, collapse = ",")]
parametros[, definicion_target := "hay_zl_problema_comparable; excluye ZL voluminosos"]
parametros[, uso_como_feature := "COM no se usa como feature ni como target principal; solo evaluacion secundaria"]
parametros[, feature_set_zl := feature_set_zl]

arrow::write_dataset(
  predicciones,
  path = file.path(out_base, "predicciones_observadas"),
  format = "parquet",
  partitioning = c("version_cluster", "escenario", "split"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)
arrow::write_dataset(
  metricas,
  path = file.path(out_base, "metricas"),
  format = "parquet",
  partitioning = c("version_cluster", "escenario"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)
arrow::write_dataset(
  lift,
  path = file.path(out_base, "lift"),
  format = "parquet",
  partitioning = c("version_cluster", "escenario"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)
arrow::write_dataset(
  calibracion,
  path = file.path(out_base, "calibracion"),
  format = "parquet",
  partitioning = c("version_cluster", "escenario"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)
arrow::write_dataset(
  importancia,
  path = file.path(out_base, "importancia_variables"),
  format = "parquet",
  partitioning = c("version_cluster", "escenario"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)
arrow::write_dataset(
  inventario_features,
  path = file.path(out_base, "inventario_features"),
  format = "parquet",
  partitioning = c("version_cluster", "escenario"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)
arrow::write_dataset(
  parametros,
  path = file.path(out_base, "parametros"),
  format = "parquet",
  partitioning = c("version_cluster", "escenario"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

saveRDS(
  list(
    temporal = list(fit = resultado_temporal$fit, prep = resultado_temporal$prep),
    random_estratificado_mes = list(fit = resultado_random$fit, prep = resultado_random$prep),
    random_dia_estratificado_mes = list(fit = resultado_random_dia$fit, prep = resultado_random_dia$prep),
    feature_set_zl = feature_set_zl,
    features_numericas = features_numericas,
    features_categoricas = features_categoricas,
    parametros = parametros
  ),
  file.path(out_base, "modelo_zl_xgboost.rds")
)

data.table::fwrite(
  resumen_base,
  file.path(out_outputs, "modelo_zl_observado_resumen_base.csv")
)
data.table::fwrite(
  resumen_splits,
  file.path(out_outputs, "modelo_zl_observado_resumen_splits.csv")
)
data.table::fwrite(
  metricas,
  file.path(out_outputs, "modelo_zl_observado_metricas.csv")
)
data.table::fwrite(
  metricas_targets,
  file.path(out_outputs, "modelo_zl_observado_metricas_targets.csv")
)
data.table::fwrite(
  metricas_random_dia_reps,
  file.path(out_outputs, "modelo_zl_observado_metricas_random_dia_reps.csv")
)
data.table::fwrite(
  resumen_random_dia_reps,
  file.path(out_outputs, "modelo_zl_observado_resumen_random_dia_reps.csv")
)
data.table::fwrite(
  lift,
  file.path(out_outputs, "modelo_zl_observado_lift.csv")
)
data.table::fwrite(
  importancia,
  file.path(out_outputs, "modelo_zl_observado_importancia.csv")
)
data.table::fwrite(
  inventario_features[order(escenario, -Gain)],
  file.path(out_outputs, "modelo_zl_observado_features_importancia.csv")
)

print(resumen_base)
print(resumen_splits)
print(metricas[order(escenario, split)])
if (nrow(metricas_random_dia_reps) > 0L) {
  print(metricas_random_dia_reps[order(rep, split)])
}
print(metricas_targets[order(target_eval, escenario, split)])
print(lift[order(escenario, split, top_pct)])
print(importancia[order(escenario, -Gain)][, head(.SD, 15), by = escenario])
