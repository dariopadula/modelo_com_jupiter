library(arrow)
library(data.table)

source("funciones/modelos_utils.R")

################################
### Parametros
path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
out_base <- "data/processed/modelos/logistico_cluster_dia"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
fecha_min_modelo <- data.table::as.IDate(Sys.getenv("FECHA_MIN_MODELO", unset = NA_character_))
target_col <- "tuvo_reclamo"

features_modelo <- c(
  "n_reclamos_lag1",
  "tuvo_reclamo_lag1",
  "sin_reclamo_previo_observado",
  "dias_historia_observada_cluster",
  "dias_desde_ultimo_reclamo_o_inicio",
  "n_reclamos_sum_7d",
  "tuvo_reclamo_sum_7d",
  "dias_cluster_existente_7d",
  "pct_dias_cluster_existente_7d",
  "n_reclamos_sum_30d",
  "tuvo_reclamo_sum_30d",
  "dias_cluster_existente_30d",
  "pct_dias_cluster_existente_30d",
  "n_contenedores_activos",
  "n_contenedores_observados",
  "n_contenedores_inferidos",
  "n_contenedores_inferencia_lejana",
  "pct_contenedores_inferidos",
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
  "mean_dias_total_tramo_inferido_estado",
  "max_dias_total_tramo_inferido_estado"
)

no_agregar_na_features <- c(
  "min_tiempo_desde_ultimo_levante_pred",
  "mean_tiempo_desde_ultimo_levante_pred",
  "median_tiempo_desde_ultimo_levante_pred",
  "max_tiempo_desde_ultimo_levante_pred",
  "min_ratio_tiempo_periodo_pred",
  "mean_ratio_tiempo_periodo_pred",
  "median_ratio_tiempo_periodo_pred",
  "max_ratio_tiempo_periodo_pred"
)

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

faltantes <- setdiff(c(target_col, features_modelo, "cluster_id", "dia", "anio_mes"), names(datos))
if (length(faltantes) > 0L) {
  stop("Faltan columnas para el modelo: ", paste(faltantes, collapse = ", "))
}

if (is.na(fecha_min_modelo)) {
  fecha_min_modelo <- min(datos$dia, na.rm = TRUE) + 7L
}

datos <- datos[dia >= fecha_min_modelo]

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

mat_train <- preparar_matriz(
  train,
  features_modelo,
  no_agregar_na_features = no_agregar_na_features
)
mat_valid <- preparar_matriz(valid, features_modelo, prep = mat_train$prep)
mat_test <- if (nrow(test) > 0L) preparar_matriz(test, features_modelo, prep = mat_train$prep) else NULL

x_train <- cbind(intercept = 1, mat_train$x)
x_valid <- cbind(intercept = 1, mat_valid$x)
x_test <- if (!is.null(mat_test)) cbind(intercept = 1, mat_test$x) else NULL

################################
### Modelo logistico
fit <- glm.fit(
  x = x_train,
  y = y_train,
  family = binomial()
)

coef_pred <- fit$coefficients
coef_no_estimable <- is.na(coef_pred)
coef_pred[coef_no_estimable] <- 0

pred_train <- as.numeric(plogis(x_train %*% coef_pred))
pred_valid <- as.numeric(plogis(x_valid %*% coef_pred))
pred_test <- if (!is.null(x_test)) as.numeric(plogis(x_test %*% coef_pred)) else numeric()

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
predicciones[, version_cluster := target_version_cluster]

lift_validacion <- lift_top(copy(predicciones_validacion))
lift_validacion[, version_cluster := target_version_cluster]

lift_diario_validacion <- lift_diario_top(copy(predicciones_validacion))
lift_diario_validacion[, version_cluster := target_version_cluster]

calibracion_validacion <- calibracion_deciles(copy(predicciones_validacion))
calibracion_validacion[, version_cluster := target_version_cluster]

coeficientes <- data.table(
  variable = names(fit$coefficients),
  coeficiente = as.numeric(fit$coefficients),
  coeficiente_usado_prediccion = as.numeric(coef_pred),
  coeficiente_no_estimable = coef_no_estimable
)
coeficientes[, odds_ratio := exp(coeficiente)]
coeficientes[, version_cluster := target_version_cluster]
coeficientes[, abs_coeficiente := abs(coeficiente)]
coeficientes[, orden_coeficiente := fifelse(is.na(abs_coeficiente), -Inf, abs_coeficiente)]
setorder(coeficientes, -orden_coeficiente)

################################
### Guardo resultados
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_base, "figuras"), recursive = TRUE, showWarnings = FALSE)
unlink(file.path(out_base, c("predicciones", "predicciones_validacion", "predicciones_test", "metricas", "lift_validacion", "lift_diario_validacion", "calibracion_validacion", "coeficientes")), recursive = TRUE)

arrow::write_dataset(
  predicciones,
  path = file.path(out_base, "predicciones"),
  format = "parquet",
  partitioning = c("version_cluster", "split"),
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

arrow::write_dataset(
  predicciones_validacion,
  path = file.path(out_base, "predicciones_validacion"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

arrow::write_dataset(
  metricas,
  path = file.path(out_base, "metricas"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

arrow::write_dataset(
  lift_validacion,
  path = file.path(out_base, "lift_validacion"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

arrow::write_dataset(
  predicciones_test,
  path = file.path(out_base, "predicciones_test"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

arrow::write_dataset(
  lift_diario_validacion,
  path = file.path(out_base, "lift_diario_validacion"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

arrow::write_dataset(
  calibracion_validacion,
  path = file.path(out_base, "calibracion_validacion"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

arrow::write_dataset(
  coeficientes,
  path = file.path(out_base, "coeficientes"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "overwrite",
  compression = "zstd"
)

saveRDS(
  list(
    fit = fit,
    coeficientes_prediccion = coef_pred,
    features_modelo = features_modelo,
    prep = mat_train$prep,
    meses_train = meses_train,
    meses_validacion = meses_validacion,
    meses_test = meses_test,
    fecha_min_modelo = fecha_min_modelo,
    no_agregar_na_features = no_agregar_na_features,
    version_cluster = target_version_cluster
  ),
  file = file.path(out_base, "modelo_logistico.rds")
)

graficar_capture_diario(
  lift_diario_validacion,
  file.path(out_base, "figuras", "capture_rate_diario.png")
)

################################
### Salida de control
print(data.table(
  version_cluster = target_version_cluster,
  fecha_min_modelo = fecha_min_modelo,
  meses_train = paste(meses_train, collapse = ","),
  meses_validacion = paste(meses_validacion, collapse = ","),
  meses_test = paste(meses_test, collapse = ",")
))
print(metricas)
print(lift_validacion)
print(lift_diario_validacion[, .(
  dias = .N,
  capture_rate_mediana = stats::median(capture_rate, na.rm = TRUE),
  capture_rate_p10 = as.numeric(stats::quantile(capture_rate, 0.1, na.rm = TRUE)),
  capture_rate_p90 = as.numeric(stats::quantile(capture_rate, 0.9, na.rm = TRUE)),
  lift_mediana = stats::median(lift, na.rm = TRUE)
), by = top_pct])
print(calibracion_validacion)
print(coeficientes[1:20])

