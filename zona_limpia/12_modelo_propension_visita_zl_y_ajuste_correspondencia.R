library(arrow)
library(data.table)
library(xgboost)

source("funciones/modelos_utils.R")

path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_comparacion_zl <- "data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia"
path_cluster_segmento <- "data/processed/cluster_territorial/cluster_segmento_censal"
path_cluster_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
out_base <- "data/processed/modelos/zona_limpia_propension_visita_xgboost"
out_outputs <- "zona_limpia/outputs"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = "v2026_05_25")
meses_modelo <- as.integer(strsplit(
  Sys.getenv("MESES_PROPENSION_VISITA_ZL", unset = "202510,202511,202512,202603,202604,202605"),
  ","
)[[1]])
municipios_excluir <- strsplit(
  Sys.getenv("MUNICIPIOS_EXCLUIR_PROPENSION_VISITA_ZL", unset = "B"),
  ","
)[[1]]
negativos_por_visita <- as.integer(Sys.getenv("NEGATIVOS_POR_VISITA_PROPENSION_ZL", unset = "3"))

set.seed(20260703)

dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_base, "modelo"), recursive = TRUE, showWarnings = FALSE)
dir.create(out_outputs, recursive = TRUE, showWarnings = FALSE)

xgb_nrounds <- 100L
xgb_params <- list(
  objective = "binary:logistic",
  eval_metric = "logloss",
  max_depth = 3L,
  eta = 0.06,
  subsample = 0.85,
  colsample_bytree = 0.85,
  min_child_weight = 40,
  nthread = 4L
)

features_numericas_operativas <- c(
  "n_contenedores_activos",
  "n_contenedores_elegibles_modelo",
  "n_contenedores_observados",
  "n_contenedores_inferidos",
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
  "max_dias_total_tramo_inferido_estado",
  "pct_contenedores_inferidos",
  "pct_contenedores_elegibles_modelo"
)

features_numericas_segmento <- c(
  "poblacion_segmento",
  "hogares_segmento",
  "viviendas_segmento",
  "viviendas_ocupadas_segmento",
  "porc_nbi_segmento",
  "porc_asentamiento_nbi_segmento",
  "porc_vivienda_inadecuada_segmento",
  "densidad_pob_km2",
  "densidad_hog_km2",
  "densidad_viv_km2",
  "cluster_multisegmento",
  "n_segmentos_posiciones",
  "pct_posiciones_segmento_principal"
)

features_numericas_admin <- c(
  "poblacion_ccz_2023",
  "viviendas_ccz_2023",
  "densidad_pob_ccz_2023_km2",
  "densidad_viv_ccz_2023_km2",
  "poblacion_barrio_2023",
  "viviendas_barrio_2023",
  "densidad_pob_barrio_2023_km2",
  "densidad_viv_barrio_2023_km2"
)

features_numericas_calendario <- c("mes_calendario", "dia_semana", "fin_de_semana")
features_numericas <- c(
  features_numericas_operativas,
  features_numericas_segmento,
  features_numericas_admin,
  features_numericas_calendario
)
features_categoricas <- c("municipio", "ccz", "nombre_barrio_ine")

leer_meses_particionados <- function(path_base, meses, version_cluster) {
  partes <- lapply(meses, function(mes) {
    anio <- substr(as.character(mes), 1, 4)
    path <- file.path(
      path_base,
      paste0("version_cluster=", version_cluster),
      paste0("anio=", anio),
      paste0("anio_mes=", mes),
      "part-0.parquet"
    )
    if (!file.exists(path)) {
      warning("No existe: ", path)
      return(NULL)
    }
    dt <- as.data.table(arrow::read_parquet(path))
    dt[, version_cluster := version_cluster]
    dt[, anio := as.integer(anio)]
    dt[, anio_mes := as.integer(mes)]
    dt
  })
  rbindlist(partes, fill = TRUE)
}

normalizar_nivel <- function(x) {
  x <- toupper(trimws(as.character(x)))
  x[is.na(x) | x == ""] <- "SIN_DATO"
  iconv(x, from = "", to = "ASCII//TRANSLIT")
}

nombre_seguro <- function(x) {
  make.names(gsub("[^A-Za-z0-9_]+", "_", x), unique = TRUE)
}

preparar_matriz_xgb <- function(dt, features_numericas, features_categoricas, prep = NULL) {
  x_num <- copy(dt[, ..features_numericas])

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

ajustar_prior <- function(p_sample, prior_real, prior_sample) {
  eps <- 1e-6
  p_sample <- pmin(pmax(p_sample, eps), 1 - eps)
  logit_sample <- qlogis(p_sample)
  offset <- qlogis(prior_real) - qlogis(prior_sample)
  plogis(logit_sample + offset)
}

dividir_seguro <- function(numerador, denominador) {
  fifelse(denominador > 0, numerador / denominador, NA_real_)
}

resumir_correspondencia <- function(dt, by_cols, peso_col = NULL, etiqueta) {
  if (is.null(peso_col)) {
    dt[, peso_tmp := 1]
  } else {
    dt[, peso_tmp := get(peso_col)]
  }

  out <- dt[
    ,
    .(
      cluster_dia_observados = .N,
      clusters_observados = uniqueN(cluster_id),
      peso_total = sum(peso_tmp, na.rm = TRUE),
      zl_problema = sum(peso_tmp * problema_zl, na.rm = TRUE),
      com = sum(peso_tmp * reclamo_com, na.rm = TRUE),
      ambos = sum(peso_tmp * (problema_zl & reclamo_com), na.rm = TRUE),
      solo_zl_problema = sum(peso_tmp * (problema_zl & !reclamo_com), na.rm = TRUE),
      solo_com_zl_limpio = sum(peso_tmp * (reclamo_com & limpio_zl & !problema_zl), na.rm = TRUE),
      ambos_sin_problema = sum(peso_tmp * (!problema_zl & !reclamo_com & limpio_zl), na.rm = TRUE),
      zl_limpio = sum(peso_tmp * limpio_zl, na.rm = TRUE)
    ),
    by = by_cols
  ][
    ,
    `:=`(
      tasa_com_dado_zl_problema = dividir_seguro(ambos, zl_problema),
      tasa_no_com_dado_zl_problema = dividir_seguro(solo_zl_problema, zl_problema),
      tasa_zl_problema_dado_com = dividir_seguro(ambos, com),
      tasa_com_con_zl_limpio = dividir_seguro(solo_com_zl_limpio, com),
      ratio_zl_problema_com = dividir_seguro(zl_problema, com),
      ratio_solo_zl_problema_com = dividir_seguro(solo_zl_problema, com),
      metodo = etiqueta
    )
  ][]

  dt[, peso_tmp := NULL]
  out
}

cat("Leyendo datos...\n")
features <- leer_meses_particionados(path_features, meses_modelo, target_version_cluster)
comparacion_zl <- leer_meses_particionados(path_comparacion_zl, meses_modelo, target_version_cluster)
cluster_segmento <- as.data.table(arrow::read_parquet(file.path(
  path_cluster_segmento,
  paste0("version_cluster=", target_version_cluster),
  "part-0.parquet"
)))
cluster_segmento[, version_cluster := target_version_cluster]
cluster_admin <- as.data.table(arrow::read_parquet(file.path(
  path_cluster_admin,
  paste0("version_cluster=", target_version_cluster),
  "part-0.parquet"
)))
cluster_admin[, version_cluster := target_version_cluster]

for (dt in list(features, comparacion_zl, cluster_segmento, cluster_admin)) {
  dt[, version_cluster := as.character(version_cluster)]
  dt[, cluster_id := as.character(cluster_id)]
}

features <- features[
  ,
  c("version_cluster", "cluster_id", "dia", "anio_mes", features_numericas_operativas),
  with = FALSE
]
comparacion_zl <- comparacion_zl[
  ,
  .(
    version_cluster,
    cluster_id,
    dia = as.IDate(dia),
    hay_zl_visita_efectiva,
    hay_zl_problema_comparable,
    hay_zl_voluminosos,
    hay_zl_limpio,
    hay_com
  )
]
cluster_segmento <- cluster_segmento[
  ,
  c("version_cluster", "cluster_id", features_numericas_segmento),
  with = FALSE
]
cluster_admin <- cluster_admin[
  ,
  c("version_cluster", "cluster_id", features_categoricas, features_numericas_admin),
  with = FALSE
]

features[, dia := as.IDate(dia)]

datos <- comparacion_zl[
  features,
  on = c("version_cluster", "cluster_id", "dia")
]

for (col in c("hay_zl_visita_efectiva", "hay_zl_problema_comparable", "hay_zl_voluminosos", "hay_zl_limpio", "hay_com")) {
  datos[is.na(get(col)), (col) := FALSE]
}

datos <- cluster_segmento[datos, on = c("version_cluster", "cluster_id")]
datos <- cluster_admin[datos, on = c("version_cluster", "cluster_id")]

datos[, municipio := toupper(trimws(as.character(municipio)))]
datos[, ccz := as.character(ccz)]
datos <- datos[!municipio %in% municipios_excluir]

datos[, target_visita_zl := as.integer(hay_zl_visita_efectiva)]
datos[, mes_calendario := as.integer(format(as.Date(dia), "%m"))]
datos[, dia_semana := as.integer(format(as.Date(dia), "%u"))]
datos[, fin_de_semana := as.integer(dia_semana %in% c(6L, 7L))]

faltantes_features <- setdiff(
  c(features_numericas, features_categoricas, "target_visita_zl"),
  names(datos)
)
if (length(faltantes_features) > 0L) {
  stop("Faltan columnas para entrenar propension de visita ZL: ", paste(faltantes_features, collapse = ", "))
}

cat("Filas universo no B: ", nrow(datos), "\n", sep = "")
cat("Visitas ZL: ", sum(datos$target_visita_zl), "\n", sep = "")

positivos <- datos[target_visita_zl == 1L]
negativos <- datos[target_visita_zl == 0L]
n_neg_sample <- min(nrow(negativos), nrow(positivos) * negativos_por_visita)
negativos_sample <- negativos[sample.int(.N, n_neg_sample)]
muestra <- rbindlist(list(positivos, negativos_sample), fill = TRUE)
muestra[, split := fifelse(runif(.N) < 0.8, "train", "validacion"), by = target_visita_zl]

prior_real <- mean(datos$target_visita_zl)
prior_sample <- mean(muestra$target_visita_zl)

train <- muestra[split == "train"]
valid <- muestra[split == "validacion"]

cat("Entrenando XGBoost liviano...\n")
mat_train <- preparar_matriz_xgb(train, features_numericas, features_categoricas)
mat_valid <- preparar_matriz_xgb(valid, features_numericas, features_categoricas, prep = mat_train$prep)

dtrain <- xgboost::xgb.DMatrix(data = mat_train$x, label = train$target_visita_zl)
dvalid <- xgboost::xgb.DMatrix(data = mat_valid$x, label = valid$target_visita_zl)

fit <- xgboost::xgb.train(
  params = xgb_params,
  data = dtrain,
  nrounds = xgb_nrounds,
  watchlist = list(train = dtrain, validacion = dvalid),
  verbose = 0
)

pred_valid_sample <- as.numeric(predict(fit, dvalid))
pred_valid_ajustada <- ajustar_prior(pred_valid_sample, prior_real, prior_sample)
metricas <- data.table(
  escenario = "validacion_muestra_control",
  n = nrow(valid),
  visitas = sum(valid$target_visita_zl),
  prevalencia_muestra = mean(valid$target_visita_zl),
  prevalencia_real = prior_real,
  auc = auc_binaria(valid$target_visita_zl, pred_valid_sample),
  logloss_ajustada_prior = logloss_binaria(valid$target_visita_zl, pred_valid_ajustada)
)

calibracion <- calibracion_deciles(
  data.table(target_visita_zl = valid$target_visita_zl, pred_propension = pred_valid_ajustada),
  score_col = "pred_propension",
  y_col = "target_visita_zl"
)
calibracion[, escenario := "validacion_muestra_control"]

importancia <- as.data.table(xgboost::xgb.importance(
  feature_names = colnames(mat_train$x),
  model = fit
))

visitas <- datos[
  hay_zl_visita_efectiva == TRUE &
    hay_zl_voluminosos != TRUE
]
visitas[, `:=`(
  problema_zl = hay_zl_problema_comparable == TRUE,
  reclamo_com = hay_com == TRUE,
  limpio_zl = hay_zl_limpio == TRUE
)]

cat("Prediciendo propension sobre visitas observadas...\n")
mat_visitas <- preparar_matriz_xgb(visitas, features_numericas, features_categoricas, prep = mat_train$prep)
visitas[, pred_propension_sample := as.numeric(predict(fit, xgboost::xgb.DMatrix(data = mat_visitas$x)))]
visitas[, pred_propension := ajustar_prior(pred_propension_sample, prior_real, prior_sample)]
visitas[, pred_propension_clip := pmin(pmax(pred_propension, 0.01), 0.99)]
visitas[, peso_ipw_estabilizado := prior_real / pred_propension_clip]
visitas[, peso_ipw_estabilizado_cap20 := pmin(peso_ipw_estabilizado, 20)]

correspondencia_global <- rbindlist(list(
  resumir_correspondencia(visitas, character(), NULL, "crudo_observado"),
  resumir_correspondencia(visitas, character(), "peso_ipw_estabilizado", "ipw_propension_muestreo"),
  resumir_correspondencia(visitas, character(), "peso_ipw_estabilizado_cap20", "ipw_propension_muestreo_cap20")
), fill = TRUE)
correspondencia_global[, `:=`(
  version_cluster = target_version_cluster,
  meses_analisis = paste(meses_modelo, collapse = ","),
  municipios_excluidos = paste(municipios_excluir, collapse = ","),
  prior_real_visita = prior_real,
  prior_muestra_entrenamiento = prior_sample
)]

correspondencia_municipio <- rbindlist(list(
  resumir_correspondencia(visitas, "municipio", NULL, "crudo_observado"),
  resumir_correspondencia(visitas, "municipio", "peso_ipw_estabilizado", "ipw_propension_muestreo"),
  resumir_correspondencia(visitas, "municipio", "peso_ipw_estabilizado_cap20", "ipw_propension_muestreo_cap20")
), fill = TRUE)[order(municipio, metodo)]

correspondencia_ccz <- rbindlist(list(
  resumir_correspondencia(visitas, c("municipio", "ccz"), NULL, "crudo_observado"),
  resumir_correspondencia(visitas, c("municipio", "ccz"), "peso_ipw_estabilizado", "ipw_propension_muestreo"),
  resumir_correspondencia(visitas, c("municipio", "ccz"), "peso_ipw_estabilizado_cap20", "ipw_propension_muestreo_cap20")
), fill = TRUE)[order(municipio, ccz, metodo)]

diagnostico_pesos <- visitas[
  ,
  .(
    n = .N,
    pred_propension_media = mean(pred_propension, na.rm = TRUE),
    pred_propension_p10 = quantile(pred_propension, 0.10, na.rm = TRUE),
    pred_propension_p50 = quantile(pred_propension, 0.50, na.rm = TRUE),
    pred_propension_p90 = quantile(pred_propension, 0.90, na.rm = TRUE),
    peso_media = mean(peso_ipw_estabilizado, na.rm = TRUE),
    peso_p50 = quantile(peso_ipw_estabilizado, 0.50, na.rm = TRUE),
    peso_p90 = quantile(peso_ipw_estabilizado, 0.90, na.rm = TRUE),
    peso_p99 = quantile(peso_ipw_estabilizado, 0.99, na.rm = TRUE),
    peso_max = max(peso_ipw_estabilizado, na.rm = TRUE),
    peso_cap20_media = mean(peso_ipw_estabilizado_cap20, na.rm = TRUE)
  ),
  by = municipio
][order(municipio)]

predicciones_visitas <- visitas[
  ,
  .(
    version_cluster,
    cluster_id,
    dia,
    anio_mes,
    municipio,
    ccz,
    pred_propension,
    peso_ipw_estabilizado,
    peso_ipw_estabilizado_cap20,
    problema_zl,
    reclamo_com
  )
]

saveRDS(
  list(
    fit = fit,
    prep = mat_train$prep,
    features_numericas = features_numericas,
    features_categoricas = features_categoricas,
    xgb_params = xgb_params,
    xgb_nrounds = xgb_nrounds,
    version_cluster = target_version_cluster,
    meses_modelo = meses_modelo,
    municipios_excluir = municipios_excluir,
    prior_real = prior_real,
    prior_sample = prior_sample
  ),
  file.path(out_base, "modelo", "modelo_propension_visita_zl_xgboost.rds")
)

fwrite(metricas, file.path(out_outputs, "propension_visita_zl_metricas.csv"))
fwrite(calibracion, file.path(out_outputs, "propension_visita_zl_calibracion.csv"))
fwrite(importancia, file.path(out_outputs, "propension_visita_zl_importancia.csv"))
fwrite(diagnostico_pesos, file.path(out_outputs, "propension_visita_zl_diagnostico_pesos.csv"))
fwrite(predicciones_visitas, file.path(out_outputs, "propension_visita_zl_predicciones_visitas.csv"))
fwrite(correspondencia_global, file.path(out_outputs, "correspondencia_com_zl_ipw_global.csv"))
fwrite(correspondencia_municipio, file.path(out_outputs, "correspondencia_com_zl_ipw_municipio.csv"))
fwrite(correspondencia_ccz, file.path(out_outputs, "correspondencia_com_zl_ipw_ccz.csv"))

print(metricas)
print(correspondencia_global)
print(correspondencia_municipio[metodo == "ipw_propension_muestreo_cap20"][order(tasa_com_dado_zl_problema)])
