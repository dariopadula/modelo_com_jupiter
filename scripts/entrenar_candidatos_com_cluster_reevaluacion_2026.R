library(arrow)
library(data.table)
library(dplyr)
library(xgboost)

source("funciones/modelos_utils.R")
source("funciones/splits_temporales.R")

set.seed(20260916)

path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_out <- "data/processed/modelos/reevaluacion_2026/com_cluster"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

features_modelo <- c(
  "n_reclamos_lag1", "sin_reclamo_previo_observado",
  "historia_observada_7_29", "historia_observada_30_89",
  "historia_observada_90_179", "historia_observada_180_mas",
  "dias_desde_ultimo_reclamo_o_inicio_trunc_90",
  "n_reclamos_sum_7d", "n_reclamos_sum_30d",
  "dias_cluster_existente_30d", "n_contenedores_activos",
  "pct_contenedores_inferidos", "mean_tiempo_desde_ultimo_levante_pred",
  "mean_levante_periodo", "mean_dias_total_tramo_inferido_estado"
)

cols_fuente <- unique(c(
  "version_cluster", "cluster_id", "dia", "n_reclamos", "tuvo_reclamo",
  "dias_historia_observada_cluster", "dias_desde_ultimo_reclamo_o_inicio",
  "tuvo_reclamo_lag1", "tuvo_reclamo_sum_7d", "tuvo_reclamo_sum_30d",
  setdiff(features_modelo, c(
    "historia_observada_7_29", "historia_observada_30_89",
    "historia_observada_90_179", "historia_observada_180_mas",
    "dias_desde_ultimo_reclamo_o_inicio_trunc_90"
  ))
))

datos <- as.data.table(as.data.frame(
  arrow::open_dataset(path_features, format = "parquet") |>
    dplyr::filter(dia <= as.Date("2026-06-30")) |>
    dplyr::select(dplyr::all_of(cols_fuente)) |>
    dplyr::collect()
))
datos[, dia := as.IDate(dia)]
version_cluster_obj <- unique(datos$version_cluster)
if (length(version_cluster_obj) != 1L) stop("Se esperaba una version_cluster")

datos <- aplicar_rezago_historia_reclamos(datos, rezago_reclamos_dias = 2L)
datos <- agregar_features_logistico_reducido(datos)
datos <- asignar_split_congelado(datos)
datos <- datos[split %in% c("entrenamiento", "validacion")]

train <- datos[split == "entrenamiento"]
valid <- datos[split == "validacion"]
if (!nrow(train) || !nrow(valid)) stop("Train o validacion vacios")

no_agregar_na <- "mean_tiempo_desde_ultimo_levante_pred"
mat_train <- preparar_matriz(
  train, features_modelo,
  no_agregar_na_features = no_agregar_na
)
mat_valid <- preparar_matriz(valid, features_modelo, prep = mat_train$prep)
x_train <- cbind(intercept = 1, mat_train$x)
x_valid <- cbind(intercept = 1, mat_valid$x)
y_train <- as.integer(train$tuvo_reclamo)

fit_logistico <- glm.fit(x_train, y_train, family = binomial())
coef_logistico <- fit_logistico$coefficients
coef_logistico[is.na(coef_logistico)] <- 0
pred_logistico <- as.numeric(plogis(x_valid %*% coef_logistico))

dtrain <- xgb.DMatrix(mat_train$x, label = y_train)
dvalid <- xgb.DMatrix(mat_valid$x)
params_xgb <- list(
  objective = "binary:logistic", eval_metric = "logloss",
  max_depth = 4L, eta = 0.05, subsample = 0.8,
  colsample_bytree = 0.8, min_child_weight = 50,
  tree_method = "hist", nthread = 4L
)
fit_xgb <- xgb.train(
  params = params_xgb, data = dtrain, nrounds = 120L, verbose = 0
)
pred_xgb <- as.numeric(predict(fit_xgb, dvalid))

predicciones <- rbindlist(list(
  valid[, .(
    version_cluster, cluster_id, dia, split,
    target = as.integer(tuvo_reclamo), n_reclamos,
    candidato = "com_logistico_reducido_d2",
    pred_prob = pred_logistico
  )],
  valid[, .(
    version_cluster, cluster_id, dia, split,
    target = as.integer(tuvo_reclamo), n_reclamos,
    candidato = "com_xgboost_d2",
    pred_prob = pred_xgb
  )]
))

saveRDS(list(
  fit = fit_logistico, coeficientes_prediccion = coef_logistico,
  prep = mat_train$prep, features = features_modelo,
  version_split = "reevaluacion_2026_v1", rezago_com_dias = 2L
), file.path(path_out, "com_logistico_reducido_d2.rds"))
saveRDS(list(
  fit = fit_xgb, prep = mat_train$prep, features = features_modelo,
  params = params_xgb, nrounds = 120L,
  version_split = "reevaluacion_2026_v1", rezago_com_dias = 2L
), file.path(path_out, "com_xgboost_d2.rds"))
arrow::write_parquet(
  predicciones,
  file.path(path_out, "predicciones_validacion.parquet"),
  compression = "zstd"
)

inventario <- data.table(
  candidato = c("com_logistico_reducido_d2", "com_xgboost_d2"),
  familia = "com_cluster",
  algoritmo = c("regresion_logistica", "xgboost"),
  filas_train = nrow(train),
  filas_validacion = nrow(valid),
  n_features = length(features_modelo),
  version_split = "reevaluacion_2026_v1",
  usa_test = FALSE,
  bootstrap = FALSE
)
fwrite(inventario, file.path(path_out, "inventario.csv"))
fwrite(data.table(feature = features_modelo), file.path(path_out, "features.csv"))
print(inventario)
