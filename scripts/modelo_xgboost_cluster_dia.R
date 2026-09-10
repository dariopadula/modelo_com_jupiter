library(arrow)
library(data.table)
library(xgboost)

source("funciones/modelos_utils.R")

################################
### Parametros
path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
out_base <- Sys.getenv("OUT_BASE_MODELO", unset = "data/processed/modelos/xgboost_cluster_dia")
out_outputs <- Sys.getenv("OUT_OUTPUTS_MODELO", unset = "outputs")
path_clima_features <- "data/processed/clima/inumet_melilla_g3/clima_inumet_melilla_g3_features_diarias.csv"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
fecha_min_modelo <- data.table::as.IDate(Sys.getenv("FECHA_MIN_MODELO", unset = NA_character_))
target_col <- "tuvo_reclamo"
usar_clima <- Sys.getenv("USAR_CLIMA", unset = "0") %in% c("1", "TRUE", "true", "SI", "si")
usar_exceso_levante <- Sys.getenv("USAR_EXCESO_LEVANTE", unset = "0") %in% c("1", "TRUE", "true", "SI", "si")
set.seed(20260525)

features_exceso_levante <- c(
  "exceso_mean_tiempo_periodo_pred_pos",
  "exceso_mean_tiempo_periodo_pred_trunc_7"
)

features_modelo <- c(
  "n_reclamos_lag1",
  "sin_reclamo_previo_observado",
  "historia_observada_7_29",
  "historia_observada_30_89",
  "historia_observada_90_179",
  "historia_observada_180_mas",
  "dias_desde_ultimo_reclamo_o_inicio_trunc_90",
  "n_reclamos_sum_7d",
  "n_reclamos_sum_30d",
  "dias_cluster_existente_30d",
  "n_contenedores_activos",
  "pct_contenedores_inferidos",
  "mean_tiempo_desde_ultimo_levante_pred",
  "mean_levante_periodo",
  "mean_dias_total_tramo_inferido_estado"
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

if (usar_clima) {
  features_modelo <- c(features_modelo, features_clima)
}
if (usar_exceso_levante) {
  features_modelo <- c(features_modelo, features_exceso_levante)
}

features_base_requeridas <- c(
  setdiff(
    features_modelo,
    c(
      "historia_observada_7_29",
      "historia_observada_30_89",
      "historia_observada_90_179",
      "historia_observada_180_mas",
      "dias_desde_ultimo_reclamo_o_inicio_trunc_90",
      features_exceso_levante
    )
  ),
  "dias_historia_observada_cluster",
  "dias_desde_ultimo_reclamo_o_inicio"
)

xgb_nrounds <- as.integer(Sys.getenv("NROUNDS_XGB", unset = "120"))
xgb_params <- list(
  objective = "binary:logistic",
  eval_metric = "logloss",
  max_depth = 4L,
  eta = 0.05,
  subsample = 0.8,
  colsample_bytree = 0.8,
  min_child_weight = 50,
  nthread = 4L
)

################################
### Helpers
preparar_matriz_xgb <- function(dt, features, imputacion = NULL) {
  x <- data.table::copy(dt[, ..features])

  for (col in names(x)) {
    if (is.logical(x[[col]])) x[, (col) := as.integer(get(col))]
    if (is.integer(x[[col]])) x[, (col) := as.numeric(get(col))]
  }

  if (is.null(imputacion)) {
    imputacion <- lapply(features, function(col) {
      vals <- x[[col]]
      med <- stats::median(vals, na.rm = TRUE)
      if (is.na(med) || is.infinite(med)) med <- 0
      list(col = col, mediana = med)
    })
    names(imputacion) <- features
  }

  for (col in features) {
    med <- imputacion[[col]]$mediana
    x[is.na(get(col)), (col) := med]
  }

  list(
    x = as.matrix(x),
    imputacion = imputacion
  )
}

################################
### Cargo datos
datos <- as.data.table(arrow::open_dataset(path_features, format = "parquet"))

if (usar_clima) {
  if (!file.exists(path_clima_features)) {
    stop("No existe tabla de features climaticas: ", path_clima_features)
  }
  clima_features <- data.table::fread(path_clima_features)
  clima_features[, dia := as.IDate(dia)]
  datos[, dia := as.IDate(dia)]
  datos <- clima_features[
    datos,
    on = "dia"
  ]
}

if (!is.na(target_version_cluster) && target_version_cluster != "") {
  datos <- datos[version_cluster == target_version_cluster]
} else {
  versiones <- sort(unique(datos$version_cluster))
  target_version_cluster <- versiones[length(versiones)]
  datos <- datos[version_cluster == target_version_cluster]
}

faltantes <- setdiff(c(target_col, features_base_requeridas, "cluster_id", "dia", "anio_mes"), names(datos))
if (length(faltantes) > 0L) {
  stop("Faltan columnas para el modelo: ", paste(faltantes, collapse = ", "))
}

if (is.na(fecha_min_modelo)) {
  fecha_min_modelo <- min(datos$dia, na.rm = TRUE) + 7L
}

datos <- datos[dia >= fecha_min_modelo]
datos <- agregar_features_logistico_reducido(datos)
if (usar_exceso_levante) {
  datos <- agregar_features_exceso_levante_periodo(datos)
}

split_meses <- definir_split_meses(
  datos[, sort(unique(anio_mes))],
  n_train = 12L,
  n_validacion = 3L,
  n_test_min = 1L
)

meses_train <- split_meses$meses_train
meses_validacion <- split_meses$meses_validacion
meses_test <- split_meses$meses_test

train <- datos[anio_mes %in% meses_train]
valid <- datos[anio_mes %in% meses_validacion]
test <- datos[anio_mes %in% meses_test]

if (nrow(train) == 0L || nrow(valid) == 0L) {
  stop("Train o validacion quedaron vacios")
}

y_train <- as.integer(train[[target_col]])
y_valid <- as.integer(valid[[target_col]])
y_test <- as.integer(test[[target_col]])

################################
### Preparo matrices
mat_train <- preparar_matriz_xgb(train, features_modelo)
mat_valid <- preparar_matriz_xgb(valid, features_modelo, imputacion = mat_train$imputacion)
mat_test <- if (nrow(test) > 0L) preparar_matriz_xgb(test, features_modelo, imputacion = mat_train$imputacion) else NULL

dtrain <- xgboost::xgb.DMatrix(
  data = mat_train$x,
  label = y_train,
  missing = NA
)

dvalid <- xgboost::xgb.DMatrix(
  data = mat_valid$x,
  label = y_valid,
  missing = NA
)

dtest <- if (!is.null(mat_test)) {
  xgboost::xgb.DMatrix(
    data = mat_test$x,
    label = y_test,
    missing = NA
  )
} else {
  NULL
}

################################
### Modelo XGBoost base
tiempo_entrenamiento <- system.time({
  fit <- xgboost::xgb.train(
    params = xgb_params,
    data = dtrain,
    nrounds = xgb_nrounds,
    watchlist = list(train = dtrain, validacion = dvalid),
    verbose = 1
  )
})

tiempo_prediccion <- system.time({
  pred_train <- as.numeric(predict(fit, dtrain))
  pred_valid <- as.numeric(predict(fit, dvalid))
  pred_test <- if (!is.null(dtest)) as.numeric(predict(fit, dtest)) else numeric()
})

################################
### Metricas
metricas <- rbindlist(list(
  data.table(
    split = "train",
    n = nrow(train),
    positivos = sum(y_train),
    prevalencia = mean(y_train),
    auc = auc_binaria(y_train, pred_train),
    logloss = logloss_binaria(y_train, pred_train)
  ),
  data.table(
    split = "validacion",
    n = nrow(valid),
    positivos = sum(y_valid),
    prevalencia = mean(y_valid),
    auc = auc_binaria(y_valid, pred_valid),
    logloss = logloss_binaria(y_valid, pred_valid)
  ),
  data.table(
    split = "test",
    n = nrow(test),
    positivos = sum(y_test),
    prevalencia = if (nrow(test) > 0L) mean(y_test) else NA_real_,
    auc = if (nrow(test) > 0L) auc_binaria(y_test, pred_test) else NA_real_,
    logloss = if (nrow(test) > 0L) logloss_binaria(y_test, pred_test) else NA_real_
  )
))
metricas[, version_cluster := target_version_cluster]

predicciones_validacion <- valid[, .(
  cluster_id,
  dia,
  anio_mes,
  split = "validacion",
  target = as.integer(get(target_col)),
  n_reclamos,
  pred_prob = pred_valid
)]
predicciones_validacion[, version_cluster := target_version_cluster]

predicciones_test <- test[, .(
  cluster_id,
  dia,
  anio_mes,
  split = "test",
  target = as.integer(get(target_col)),
  n_reclamos,
  pred_prob = pred_test
)]
predicciones_test[, version_cluster := target_version_cluster]

predicciones <- rbindlist(list(predicciones_validacion, predicciones_test), use.names = TRUE)

lift_validacion <- lift_top(copy(predicciones_validacion))
lift_validacion[, version_cluster := target_version_cluster]

lift_diario_validacion <- lift_diario_top(copy(predicciones_validacion))
lift_diario_validacion[, version_cluster := target_version_cluster]

calibracion_validacion <- calibracion_deciles(copy(predicciones_validacion))
calibracion_validacion[, version_cluster := target_version_cluster]

importancia_variables <- as.data.table(xgboost::xgb.importance(
  feature_names = features_modelo,
  model = fit
))
importancia_variables[, version_cluster := target_version_cluster]

inventario_features <- data.table(
  modelo = "xgboost_com",
  variante = fifelse(
    usar_clima & usar_exceso_levante,
    "base_clima_exceso_levante",
    fifelse(
      usar_clima,
      "base_clima",
      fifelse(usar_exceso_levante, "base_exceso_levante", "base")
    )
  ),
  feature = features_modelo
)
inventario_features[, familia := fcase(
  feature %in% features_clima, "clima",
  feature %in% features_exceso_levante, "exceso_levante",
  grepl("reclamo|historia", feature), "reclamos_historicos",
  grepl("levante|tiempo|periodo|tramo", feature), "levante",
  grepl("contenedor|inferido|elegible", feature), "contenedores",
  default = "otra"
)]
inventario_features <- importancia_variables[
  inventario_features,
  on = c(Feature = "feature")
]
setnames(inventario_features, "Feature", "feature")
inventario_features[is.na(Gain), `:=`(Gain = 0, Cover = 0, Frequency = 0)]
inventario_features[, version_cluster := target_version_cluster]

parametros <- data.table(
  version_cluster = target_version_cluster,
  fecha_min_modelo = fecha_min_modelo,
  meses_train = paste(meses_train, collapse = ","),
  meses_validacion = paste(meses_validacion, collapse = ","),
  meses_test = paste(meses_test, collapse = ","),
  nrounds = xgb_nrounds,
  max_depth = xgb_params$max_depth,
  eta = xgb_params$eta,
  subsample = xgb_params$subsample,
  colsample_bytree = xgb_params$colsample_bytree,
  min_child_weight = xgb_params$min_child_weight,
  nthread = xgb_params$nthread,
  usar_clima = usar_clima,
  usar_exceso_levante = usar_exceso_levante,
  n_features_modelo = length(features_modelo),
  n_features_clima = if (usar_clima) length(features_clima) else 0L,
  n_features_exceso_levante = if (usar_exceso_levante) length(features_exceso_levante) else 0L,
  segundos_entrenamiento = as.numeric(tiempo_entrenamiento[["elapsed"]]),
  segundos_prediccion = as.numeric(tiempo_prediccion[["elapsed"]])
)

################################
### Guardo resultados
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_base, "figuras"), recursive = TRUE, showWarnings = FALSE)
dir.create(out_outputs, recursive = TRUE, showWarnings = FALSE)
unlink(
  file.path(out_base, c(
    "predicciones",
    "predicciones_validacion",
    "predicciones_test",
    "metricas",
    "lift_validacion",
    "lift_diario_validacion",
    "calibracion_validacion",
    "importancia_variables",
    "inventario_features",
    "parametros"
  )),
  recursive = TRUE
)

arrow::write_dataset(predicciones, file.path(out_base, "predicciones"), format = "parquet", partitioning = c("version_cluster", "split"), existing_data_behavior = "overwrite", compression = "zstd")
arrow::write_dataset(predicciones_validacion, file.path(out_base, "predicciones_validacion"), format = "parquet", partitioning = "version_cluster", existing_data_behavior = "overwrite", compression = "zstd")
arrow::write_dataset(predicciones_test, file.path(out_base, "predicciones_test"), format = "parquet", partitioning = "version_cluster", existing_data_behavior = "overwrite", compression = "zstd")
arrow::write_dataset(metricas, file.path(out_base, "metricas"), format = "parquet", partitioning = "version_cluster", existing_data_behavior = "overwrite", compression = "zstd")
arrow::write_dataset(lift_validacion, file.path(out_base, "lift_validacion"), format = "parquet", partitioning = "version_cluster", existing_data_behavior = "overwrite", compression = "zstd")
arrow::write_dataset(lift_diario_validacion, file.path(out_base, "lift_diario_validacion"), format = "parquet", partitioning = "version_cluster", existing_data_behavior = "overwrite", compression = "zstd")
arrow::write_dataset(calibracion_validacion, file.path(out_base, "calibracion_validacion"), format = "parquet", partitioning = "version_cluster", existing_data_behavior = "overwrite", compression = "zstd")
arrow::write_dataset(importancia_variables, file.path(out_base, "importancia_variables"), format = "parquet", partitioning = "version_cluster", existing_data_behavior = "overwrite", compression = "zstd")
arrow::write_dataset(inventario_features, file.path(out_base, "inventario_features"), format = "parquet", partitioning = "version_cluster", existing_data_behavior = "overwrite", compression = "zstd")
arrow::write_dataset(parametros, file.path(out_base, "parametros"), format = "parquet", partitioning = "version_cluster", existing_data_behavior = "overwrite", compression = "zstd")

data.table::fwrite(
  inventario_features[order(-Gain)],
  file.path(out_outputs, paste0("xgboost_com_", unique(inventario_features$variante), "_features_importancia.csv"))
)
data.table::fwrite(
  metricas,
  file.path(out_outputs, paste0("xgboost_com_", unique(inventario_features$variante), "_metricas.csv"))
)

saveRDS(
  list(
    fit = fit,
    features_modelo = features_modelo,
    imputacion = mat_train$imputacion,
    meses_train = meses_train,
    meses_validacion = meses_validacion,
    meses_test = meses_test,
    fecha_min_modelo = fecha_min_modelo,
    usar_clima = usar_clima,
    usar_exceso_levante = usar_exceso_levante,
    parametros = parametros,
    version_cluster = target_version_cluster
  ),
  file = file.path(out_base, "modelo_xgboost.rds")
)

graficar_capture_diario(
  lift_diario_validacion,
  file.path(out_base, "figuras", "capture_rate_diario.png")
)

################################
### Salida de control
print(parametros)
print(metricas)
print(lift_validacion)
print(importancia_variables)
