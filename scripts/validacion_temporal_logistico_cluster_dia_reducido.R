library(arrow)
library(data.table)

source("funciones/modelos_utils.R")

################################
### Parametros
path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
out_base <- "data/processed/modelos/logistico_cluster_dia_reducido/validacion_temporal"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
fecha_min_modelo <- data.table::as.IDate(Sys.getenv("FECHA_MIN_MODELO", unset = NA_character_))
target_col <- "tuvo_reclamo"

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

no_agregar_na_features <- c(
  "mean_tiempo_desde_ultimo_levante_pred"
)

features_base_requeridas <- c(
  setdiff(
    features_modelo,
    c(
      "historia_observada_7_29",
      "historia_observada_30_89",
      "historia_observada_90_179",
      "historia_observada_180_mas",
      "dias_desde_ultimo_reclamo_o_inicio_trunc_90"
    )
  ),
  "dias_historia_observada_cluster",
  "dias_desde_ultimo_reclamo_o_inicio"
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

faltantes <- setdiff(c(target_col, features_base_requeridas, "cluster_id", "dia", "anio_mes"), names(datos))
if (length(faltantes) > 0L) {
  stop("Faltan columnas para validacion temporal: ", paste(faltantes, collapse = ", "))
}

if (is.na(fecha_min_modelo)) {
  fecha_min_modelo <- min(datos$dia, na.rm = TRUE) + 7L
}

datos <- datos[dia >= fecha_min_modelo]
datos <- agregar_features_logistico_reducido(datos)

split_meses <- definir_split_meses(
  datos[, sort(unique(anio_mes))],
  n_train = 12L,
  n_validacion = 3L,
  n_test_min = 1L
)

folds <- crear_folds_validacion_temporal(
  split_meses$meses,
  n_train = 12L,
  meses_validacion_final = split_meses$meses_validacion,
  meses_test = split_meses$meses_test
)

if (length(folds) == 0L) {
  stop("No se pudieron crear folds de validacion temporal")
}

################################
### Entreno folds
resultados <- lapply(folds, function(fold_info) {
  train <- datos[anio_mes %in% fold_info$meses_train]
  valid <- datos[anio_mes == fold_info$mes_validacion]

  y_train <- as.integer(train[[target_col]])
  y_valid <- as.integer(valid[[target_col]])

  mat_train <- preparar_matriz(
    train,
    features_modelo,
    no_agregar_na_features = no_agregar_na_features
  )
  mat_valid <- preparar_matriz(valid, features_modelo, prep = mat_train$prep)

  x_train <- cbind(intercept = 1, mat_train$x)
  x_valid <- cbind(intercept = 1, mat_valid$x)

  fit <- glm.fit(
    x = x_train,
    y = y_train,
    family = binomial()
  )

  coef_pred <- fit$coefficients
  coef_pred[is.na(coef_pred)] <- 0

  pred_valid <- as.numeric(plogis(x_valid %*% coef_pred))

  predicciones <- valid[, .(
    cluster_id,
    dia,
    anio_mes,
    target = as.integer(get(target_col)),
    n_reclamos,
    pred_prob = pred_valid
  )]

  metricas <- data.table(
    fold = fold_info$fold,
    mes_validacion = fold_info$mes_validacion,
    meses_train = paste(fold_info$meses_train, collapse = ","),
    n_train = nrow(train),
    n_validacion = nrow(valid),
    positivos_validacion = sum(y_valid),
    prevalencia_validacion = mean(y_valid),
    auc = auc_binaria(y_valid, pred_valid),
    logloss = logloss_binaria(y_valid, pred_valid)
  )

  lift <- lift_top(copy(predicciones))
  lift[, `:=`(
    fold = fold_info$fold,
    mes_validacion = fold_info$mes_validacion
  )]

  list(metricas = metricas, lift = lift)
})

metricas_folds <- rbindlist(lapply(resultados, `[[`, "metricas"))
lift_folds <- rbindlist(lapply(resultados, `[[`, "lift"))

metricas_resumen <- metricas_folds[
  ,
  .(
    folds = .N,
    auc_media = mean(auc, na.rm = TRUE),
    auc_min = min(auc, na.rm = TRUE),
    auc_max = max(auc, na.rm = TRUE),
    logloss_media = mean(logloss, na.rm = TRUE),
    logloss_min = min(logloss, na.rm = TRUE),
    logloss_max = max(logloss, na.rm = TRUE)
  )
]

lift_resumen <- lift_folds[
  ,
  .(
    folds = .N,
    precision_media = mean(precision, na.rm = TRUE),
    capture_rate_media = mean(capture_rate, na.rm = TRUE),
    lift_media = mean(lift, na.rm = TRUE),
    lift_min = min(lift, na.rm = TRUE),
    lift_max = max(lift, na.rm = TRUE)
  ),
  by = top_pct
][
  order(top_pct)
]

for (dt in list(metricas_folds, lift_folds, metricas_resumen, lift_resumen)) {
  dt[, `:=`(
    version_cluster = target_version_cluster,
    fecha_min_modelo = fecha_min_modelo,
    meses_test = paste(split_meses$meses_test, collapse = ",")
  )]
}

################################
### Guardo resultados
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
unlink(
  file.path(out_base, c("metricas_folds", "lift_folds", "metricas_resumen", "lift_resumen")),
  recursive = TRUE
)

arrow::write_dataset(metricas_folds, file.path(out_base, "metricas_folds"), format = "parquet", existing_data_behavior = "overwrite", compression = "zstd")
arrow::write_dataset(lift_folds, file.path(out_base, "lift_folds"), format = "parquet", existing_data_behavior = "overwrite", compression = "zstd")
arrow::write_dataset(metricas_resumen, file.path(out_base, "metricas_resumen"), format = "parquet", existing_data_behavior = "overwrite", compression = "zstd")
arrow::write_dataset(lift_resumen, file.path(out_base, "lift_resumen"), format = "parquet", existing_data_behavior = "overwrite", compression = "zstd")

################################
### Salida de control
print(metricas_folds)
print(metricas_resumen)
print(lift_resumen)
