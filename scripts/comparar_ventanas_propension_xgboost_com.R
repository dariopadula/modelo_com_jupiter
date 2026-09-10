library(arrow)
library(data.table)
library(xgboost)

set.seed(20260826)

ventanas <- c(7L, 15L, 30L, 60L, 90L)
rezago <- 2L
fuerza_prior_barrio <- 30
fuerza_prior_global <- 200
tope_exceso <- 3

path_pred <- paste0(
  "app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia/",
  "modelo_id=com_reclamo"
)
path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
path_segmento <- "data/processed/cluster_territorial/cluster_segmento_censal"
path_a0 <- file.path(
  "outputs", "prueba_xgboost_correccion_estructural_com",
  "base_a0_oof_segmento_dia.csv"
)
path_out <- "outputs/comparacion_ventanas_propension_xgboost_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

rolling_previo <- function(x, n, rezago = 2L) {
  acumulado <- cumsum(x)
  shift(acumulado, rezago, fill = 0) -
    shift(acumulado, n + rezago, fill = 0)
}

pred <- as.data.table(as.data.frame(
  open_dataset(path_pred) |>
    dplyr::select(
      cluster_id, dia_objetivo, version_cluster, tuvo_reclamo_observado
    ) |>
    dplyr::collect()
))
pred[, dia_objetivo := as.IDate(dia_objetivo)]
pred <- pred[!is.na(tuvo_reclamo_observado)]
pred[, y := as.integer(tuvo_reclamo_observado == 1L)]
version_cluster_obj <- unique(pred$version_cluster)
if (length(version_cluster_obj) != 1L) stop("Se esperaba una version_cluster")

features <- as.data.table(as.data.frame(
  open_dataset(path_features) |>
    dplyr::filter(version_cluster %in% version_cluster_obj) |>
    dplyr::select(
      cluster_id, dia, version_cluster,
      mean_tiempo_desde_ultimo_levante_pred,
      mean_levante_periodo,
      mean_ratio_tiempo_periodo_pred
    ) |>
    dplyr::collect()
))
setnames(features, "dia", "dia_objetivo")
features[, dia_objetivo := as.IDate(dia_objetivo)]

admin <- as.data.table(as.data.frame(open_dataset(path_admin)))[
  version_cluster == version_cluster_obj,
  .(cluster_id, barrio = nombre_barrio_ine)
]
segmento <- as.data.table(as.data.frame(open_dataset(path_segmento)))[
  version_cluster == version_cluster_obj,
  .(cluster_id, segmento = as.character(codseg_centroide))
]
geo <- segmento[admin, on = "cluster_id"]
if (anyDuplicated(geo$cluster_id)) stop("Cluster duplicado en geografia")

datos <- features[pred, on = c("cluster_id", "dia_objetivo", "version_cluster")]
datos <- geo[datos, on = "cluster_id"]
datos[is.na(barrio) | !nzchar(barrio), barrio := "SIN_BARRIO"]
datos[is.na(segmento) | !nzchar(segmento), segmento := "SIN_SEGMENTO"]
setorder(datos, cluster_id, dia_objetivo)

# Historias parciales del cluster. Con cero observaciones propias, la
# propension se reduce exactamente al prior barrial del mismo horizonte.
for (L in ventanas) {
  datos[, paste0("eventos_c_", L) := rolling_previo(y, L, rezago),
    by = cluster_id]
  datos[, paste0("expo_c_", L) := rolling_previo(rep(1, .N), L, rezago),
    by = cluster_id]
}

barrio_dia <- datos[, .(eventos = sum(y), exposicion = .N),
  by = .(barrio, dia_objetivo)]
setorder(barrio_dia, barrio, dia_objetivo)
global_dia <- barrio_dia[, .(
  eventos = sum(eventos), exposicion = sum(exposicion)
), by = dia_objetivo]
setorder(global_dia, dia_objetivo)

for (L in ventanas) {
  global_dia[, paste0("eventos_g_", L) := rolling_previo(eventos, L, rezago)]
  global_dia[, paste0("expo_g_", L) := rolling_previo(exposicion, L, rezago)]
  global_dia[, paste0("q_g_", L) :=
    get(paste0("eventos_g_", L)) / get(paste0("expo_g_", L))]

  barrio_dia[, paste0("eventos_b_", L) := rolling_previo(eventos, L, rezago),
    by = barrio]
  barrio_dia[, paste0("expo_b_", L) := rolling_previo(exposicion, L, rezago),
    by = barrio]
  col_qg <- paste0("q_g_", L)
  barrio_dia[global_dia, on = "dia_objetivo",
    (col_qg) := get(paste0("i.", col_qg))]
  barrio_dia[, paste0("q_b_", L) := (
    get(paste0("eventos_b_", L)) +
      fuerza_prior_global * get(paste0("q_g_", L))
  ) / (
    get(paste0("expo_b_", L)) + fuerza_prior_global
  )]
}

columnas_qb <- paste0("q_b_", ventanas)
for (col in columnas_qb) {
  datos[barrio_dia, on = c("barrio", "dia_objetivo"),
    (col) := get(paste0("i.", col))]
}

for (L in ventanas) {
  datos[, paste0("q_", L) := (
    get(paste0("eventos_c_", L)) +
      fuerza_prior_barrio * get(paste0("q_b_", L))
  ) / (
    get(paste0("expo_c_", L)) + fuerza_prior_barrio
  )]
}

datos[, exceso := pmax(mean_ratio_tiempo_periodo_pred - 1, 0)]
datos[, h_exceso := pmin(exceso, tope_exceso)]
for (L in ventanas) datos[, paste0("w_", L) := get(paste0("q_", L)) * h_exceso]

q_validas <- datos[, Reduce(`&`, lapply(.SD, is.finite)),
  .SDcols = paste0("q_", ventanas)]
datos <- datos[
  dia_objetivo >= as.IDate("2025-04-01") &
    is.finite(mean_tiempo_desde_ultimo_levante_pred) &
    is.finite(mean_levante_periodo) &
    is.finite(mean_ratio_tiempo_periodo_pred) & q_validas
]

base <- datos[, {
  k_top20_h <- max(1L, ceiling(.N * 0.20))
  salida <- list(
    n_clusters = .N,
    observado = sum(y),
    media_tiempo_levante = mean(mean_tiempo_desde_ultimo_levante_pred),
    media_periodo = mean(mean_levante_periodo),
    media_ratio = mean(mean_ratio_tiempo_periodo_pred),
    media_h = mean(h_exceso),
    media_top20_h = mean(head(sort(h_exceso, decreasing = TRUE), k_top20_h)),
    prop_exceso_positivo = mean(h_exceso > 0),
    prop_exceso_mayor_1 = mean(h_exceso > 1)
  )
  for (L in ventanas) {
    q <- get(paste0("q_", L))
    w <- get(paste0("w_", L))
    salida[[paste0("media_q_", L)]] <- mean(q)
    salida[[paste0("rms_q_", L)]] <- sqrt(mean(q^2))
    salida[[paste0("media_w_", L)]] <- mean(w)
    salida[[paste0("rms_w_", L)]] <- sqrt(mean(w^2))
  }
  salida
}, by = .(dia_objetivo, barrio, segmento)]

a0 <- fread(path_a0)
a0[, `:=`(
  dia_objetivo = as.IDate(dia_objetivo),
  segmento = as.character(segmento)
)]
base[, segmento := as.character(segmento)]
base[a0, on = c("dia_objetivo", "barrio", "segmento"), `:=`(
  split_modelo = i.split_modelo,
  dia_semana = i.dia_semana,
  prob_a0 = i.prob_a0,
  margen_a0 = i.margen_a0
)]
base <- base[
  split_modelo %in% c("entrenamiento", "validacion", "test") &
    is.finite(prob_a0) & is.finite(margen_a0)
]
base[, `:=`(
  dia_semana = factor(dia_semana),
  prop_reclamo = observado / n_clusters
)]

features_levante <- c(
  "media_tiempo_levante", "media_periodo", "media_ratio", "media_h",
  "prop_exceso_positivo", "prop_exceso_mayor_1"
)
crear_matriz <- function(dt, L) {
  vars <- c(
    features_levante, paste0(c("media_q_", "rms_q_", "media_w_", "rms_w_"), L)
  )
  model.matrix(as.formula(paste(
    "~ dia_semana +", paste(vars, collapse = " + "), "- 1"
  )), data = dt)
}

idx_fit <- which(base$split_modelo == "entrenamiento" &
  base$dia_objetivo < as.IDate("2025-11-01"))
idx_es <- which(base$split_modelo == "entrenamiento" &
  base$dia_objetivo >= as.IDate("2025-11-01"))
idx_train <- which(base$split_modelo == "entrenamiento")

params <- list(
  objective = "binary:logistic", eval_metric = "logloss",
  eta = 0.03, max_depth = 3L, min_child_weight = 100,
  subsample = 0.80, colsample_bytree = 0.80,
  lambda = 10, alpha = 0, tree_method = "hist", nthread = 4L
)

ajustes <- list()
predicciones <- list()
diagnosticos <- list()
for (L in ventanas) {
  X <- crear_matriz(base, L)
  construir_dmat <- function(idx) {
    d <- xgb.DMatrix(
      X[idx, , drop = FALSE], label = base$prop_reclamo[idx],
      weight = base$n_clusters[idx]
    )
    setinfo(d, "base_margin", base$margen_a0[idx])
    d
  }
  dfit <- construir_dmat(idx_fit)
  des <- construir_dmat(idx_es)
  fit_es <- xgb.train(
    params = params, data = dfit, nrounds = 800L,
    watchlist = list(train = dfit, seleccion = des),
    early_stopping_rounds = 40L, verbose = 0
  )
  mejor_iter <- fit_es$best_iteration
  dtrain <- construir_dmat(idx_train)
  fit <- xgb.train(
    params = params, data = dtrain, nrounds = mejor_iter, verbose = 0
  )
  dnew <- xgb.DMatrix(X)
  setinfo(dnew, "base_margin", base$margen_a0)
  prob <- as.numeric(predict(fit, dnew))
  nombre <- paste0("X2_W", L)
  ajustes[[nombre]] <- fit
  predicciones[[nombre]] <- base[, .(
    dia_objetivo, split_modelo, n_clusters, observado
  )][, `:=`(escenario = nombre, prob_predicha = prob)]
  diagnosticos[[nombre]] <- data.table(
    escenario = nombre, ventana = L, filas = nrow(base),
    mejor_iteracion = mejor_iter, logloss_seleccion = fit_es$best_score
  )
  saveRDS(fit, file.path(path_out, paste0("modelo_", nombre, ".rds")))
}

pred <- rbindlist(predicciones)
pred[, predicho_segmento := n_clusters * prob_predicha]
pred_dia <- pred[, .(
  observado = sum(observado), predicho = sum(predicho_segmento)
), by = .(escenario, split_modelo, dia_objetivo)]
pred_dia[, mes := format(dia_objetivo, "%Y-%m")]

metricas_fun <- function(dt, grupos) {
  dt[, {
    error <- predicho - observado
    .(
      dias = .N, media_observada = mean(observado),
      media_predicha = mean(predicho), sesgo = mean(error),
      mae = mean(abs(error)), rmse = sqrt(mean(error^2)),
      correlacion = cor(observado, predicho),
      razon_sd = sd(predicho) / sd(observado)
    )
  }, by = grupos]
}

metricas_periodo <- metricas_fun(
  pred_dia[split_modelo %in% c("validacion", "test")],
  c("escenario", "split_modelo")
)
metricas_combinadas <- metricas_fun(
  pred_dia[split_modelo %in% c("validacion", "test")], "escenario"
)[, split_modelo := "validacion + test"]
setcolorder(metricas_combinadas, names(metricas_periodo))
metricas_periodo <- rbindlist(list(metricas_periodo, metricas_combinadas))
metricas_mensuales <- metricas_fun(pred_dia, c("escenario", "mes"))

fwrite(base, file.path(path_out, "base_segmento_dia_ventanas.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnostico_modelos.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas_periodo, file.path(path_out, "metricas_periodo.csv"))
fwrite(metricas_mensuales, file.path(path_out, "metricas_mensuales.csv"))
fwrite(data.table(
  ventanas = paste(ventanas, collapse = ","), rezago = rezago,
  fuerza_prior_barrio = fuerza_prior_barrio,
  fuerza_prior_global = fuerza_prior_global,
  tope_exceso = tope_exceso
), file.path(path_out, "parametros.csv"))

print(rbindlist(diagnosticos))
print(metricas_periodo[split_modelo == "validacion"][order(rmse)])
print(metricas_periodo[split_modelo == "test"][order(rmse)])
print(metricas_periodo[split_modelo == "validacion + test"][order(rmse)])
