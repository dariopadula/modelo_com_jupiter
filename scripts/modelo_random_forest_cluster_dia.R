library(arrow)
library(data.table)
library(ranger)

source("funciones/modelos_utils.R")

################################
### Parametros
path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
out_base <- Sys.getenv(
  "OUT_BASE_MODELO",
  unset = "data/processed/modelos/random_forest_cluster_dia"
)

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
fecha_min_modelo <- data.table::as.IDate(Sys.getenv("FECHA_MIN_MODELO", unset = NA_character_))
target_col <- "tuvo_reclamo"
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

rf_num_trees <- 300L
rf_mtry <- floor(sqrt(length(features_modelo)))
rf_min_node_size <- 200L
rf_num_threads <- max(1L, parallel::detectCores(logical = TRUE) - 1L)

################################
### Helpers
preparar_datos_rf <- function(dt, features, target_col, imputacion = NULL) {
  x <- data.table::copy(dt[, c(target_col, features), with = FALSE])

  for (col in features) {
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

  x[, (target_col) := factor(
    data.table::fifelse(get(target_col) == TRUE, "si", "no"),
    levels = c("no", "si")
  )]

  list(datos = as.data.frame(x), imputacion = imputacion)
}

################################
### Cargo datos
datos <- as.data.table(arrow::open_dataset(path_features, format = "parquet"))

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

################################
### Preparo datos
prep_train <- preparar_datos_rf(train, features_modelo, target_col)
prep_valid <- preparar_datos_rf(valid, features_modelo, target_col, imputacion = prep_train$imputacion)
prep_test <- if (nrow(test) > 0L) {
  preparar_datos_rf(test, features_modelo, target_col, imputacion = prep_train$imputacion)
} else {
  NULL
}

################################
### Modelo Random Forest base
tiempo_entrenamiento <- system.time({
  fit <- ranger::ranger(
    dependent.variable.name = target_col,
    data = prep_train$datos,
    probability = TRUE,
    num.trees = rf_num_trees,
    mtry = rf_mtry,
    min.node.size = rf_min_node_size,
    importance = "impurity",
    num.threads = rf_num_threads,
    seed = 20260525
  )
})

tiempo_prediccion <- system.time({
  pred_train <- predict(fit, data = prep_train$datos, num.threads = rf_num_threads)$predictions[, "si"]
  pred_valid <- predict(fit, data = prep_valid$datos, num.threads = rf_num_threads)$predictions[, "si"]
  pred_test <- if (!is.null(prep_test)) {
    predict(fit, data = prep_test$datos, num.threads = rf_num_threads)$predictions[, "si"]
  } else {
    numeric()
  }
})

y_train <- as.integer(train[[target_col]])
y_valid <- as.integer(valid[[target_col]])
y_test <- as.integer(test[[target_col]])

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

importancia_variables <- data.table(
  variable = names(fit$variable.importance),
  importancia = as.numeric(fit$variable.importance)
)
importancia_variables[, version_cluster := target_version_cluster]
setorder(importancia_variables, -importancia)

parametros <- data.table(
  version_cluster = target_version_cluster,
  fecha_min_modelo = fecha_min_modelo,
  meses_train = paste(meses_train, collapse = ","),
  meses_validacion = paste(meses_validacion, collapse = ","),
  meses_test = paste(meses_test, collapse = ","),
  num_trees = rf_num_trees,
  mtry = rf_mtry,
  min_node_size = rf_min_node_size,
  num_threads = rf_num_threads,
  usar_exceso_levante = usar_exceso_levante,
  n_features_modelo = length(features_modelo),
  n_features_exceso_levante = if (usar_exceso_levante) length(features_exceso_levante) else 0L,
  segundos_entrenamiento = as.numeric(tiempo_entrenamiento[["elapsed"]]),
  segundos_prediccion = as.numeric(tiempo_prediccion[["elapsed"]])
)

################################
### Guardo resultados
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_base, "figuras"), recursive = TRUE, showWarnings = FALSE)
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
arrow::write_dataset(parametros, file.path(out_base, "parametros"), format = "parquet", partitioning = "version_cluster", existing_data_behavior = "overwrite", compression = "zstd")

saveRDS(
  list(
    fit = fit,
    features_modelo = features_modelo,
    imputacion = prep_train$imputacion,
    meses_train = meses_train,
    meses_validacion = meses_validacion,
    meses_test = meses_test,
    fecha_min_modelo = fecha_min_modelo,
    parametros = parametros,
    version_cluster = target_version_cluster
  ),
  file = file.path(out_base, "modelo_random_forest.rds")
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
