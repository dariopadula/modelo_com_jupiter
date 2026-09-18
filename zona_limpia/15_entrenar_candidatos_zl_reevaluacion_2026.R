library(arrow)
library(data.table)
library(dplyr)
library(xgboost)

source("funciones/splits_temporales.R")

set.seed(20260916)

path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_zl <- "data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia"
path_segmento <- "data/processed/cluster_territorial/cluster_segmento_censal"
path_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
path_feriados <- "data/reference/feriados/feriados.R"
path_out <- "data/processed/modelos/reevaluacion_2026/zona_limpia"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

features_contenedores <- c(
  "n_contenedores_activos", "n_contenedores_elegibles_modelo",
  "n_contenedores_observados", "n_contenedores_inferidos",
  "pct_contenedores_inferidos", "pct_contenedores_elegibles_modelo"
)
features_levante <- c(
  "min_tiempo_desde_ultimo_levante_pred",
  "mean_tiempo_desde_ultimo_levante_pred",
  "median_tiempo_desde_ultimo_levante_pred",
  "max_tiempo_desde_ultimo_levante_pred",
  "min_ratio_tiempo_periodo_pred", "mean_ratio_tiempo_periodo_pred",
  "median_ratio_tiempo_periodo_pred", "max_ratio_tiempo_periodo_pred",
  "min_levante_periodo", "mean_levante_periodo", "max_levante_periodo",
  "exceso_min_tiempo_periodo_pred_pos",
  "exceso_mean_tiempo_periodo_pred_pos",
  "exceso_max_tiempo_periodo_pred_pos",
  "exceso_min_tiempo_periodo_pred_trunc7",
  "exceso_mean_tiempo_periodo_pred_trunc7",
  "exceso_max_tiempo_periodo_pred_trunc7",
  "mean_dias_total_tramo_inferido_estado",
  "max_dias_total_tramo_inferido_estado"
)
features_calendario <- c(
  "dia_semana", "fin_de_semana", "es_feriado",
  "vispera_feriado", "dia_habil"
)
features_segmento_parsimonioso <- c(
  "porc_nbi_segmento", "porc_asentamiento_nbi_segmento",
  "porc_vivienda_inadecuada_segmento", "densidad_pob_km2",
  "cluster_multisegmento", "pct_posiciones_segmento_principal"
)
features_segmento_amplio <- c(
  "poblacion_segmento", "hogares_segmento", "viviendas_segmento",
  "viviendas_ocupadas_segmento", features_segmento_parsimonioso,
  "densidad_hog_km2", "densidad_viv_km2", "n_segmentos_posiciones"
)
features_segmento_demografia <- c(
  features_segmento_parsimonioso,
  "poblacion_segmento", "hogares_segmento", "viviendas_segmento"
)
features_agregados <- c(
  "poblacion_ccz_2023", "viviendas_ccz_2023",
  "densidad_pob_ccz_2023_km2", "densidad_viv_ccz_2023_km2",
  "poblacion_barrio_2023", "viviendas_barrio_2023",
  "densidad_pob_barrio_2023_km2", "densidad_viv_barrio_2023_km2"
)

feature_sets <- list(
  operativo_segmento = list(
    numericas = c(
      features_contenedores, features_levante,
      features_segmento_parsimonioso, features_calendario
    ),
    categoricas = character()
  ),
  operativo_segmento_demografia = list(
    numericas = c(
      features_contenedores, features_levante,
      features_segmento_demografia, features_calendario
    ),
    categoricas = character()
  ),
  amplio_actual = list(
    numericas = c(
      features_contenedores, features_levante, features_segmento_amplio,
      features_agregados, "mes_calendario", features_calendario
    ),
    categoricas = c("municipio", "ccz", "nombre_barrio_ine")
  )
)

normalizar_nivel <- function(x) {
  x <- toupper(trimws(as.character(x)))
  x[is.na(x) | x == ""] <- "SIN_DATO"
  iconv(x, from = "", to = "ASCII//TRANSLIT")
}

preparar_matriz <- function(dt, numericas, categoricas, prep = NULL) {
  x_num <- copy(dt[, ..numericas])
  for (col in names(x_num)) {
    if (is.logical(x_num[[col]])) x_num[, (col) := as.integer(get(col))]
    if (is.integer(x_num[[col]])) x_num[, (col) := as.numeric(get(col))]
  }
  if (is.null(prep)) {
    medianas <- lapply(numericas, function(col) {
      med <- median(x_num[[col]], na.rm = TRUE)
      if (!is.finite(med)) med <- 0
      med
    })
    names(medianas) <- numericas
    niveles <- lapply(categoricas, function(col) {
      sort(unique(c(normalizar_nivel(dt[[col]]), "OTRO", "SIN_DATO")))
    })
    names(niveles) <- categoricas
    prep <- list(medianas = medianas, niveles = niveles)
  }
  for (col in numericas) {
    x_num[!is.finite(get(col)), (col) := prep$medianas[[col]]]
  }
  mats <- list(as.matrix(x_num))
  for (col in categoricas) {
    vals <- normalizar_nivel(dt[[col]])
    vals[!vals %in% prep$niveles[[col]]] <- "OTRO"
    vals <- factor(vals, levels = prep$niveles[[col]])
    mm <- model.matrix(~ vals - 1)
    colnames(mm) <- paste0(col, "__", make.names(levels(vals), unique = TRUE))
    mats[[length(mats) + 1L]] <- mm
  }
  x <- do.call(cbind, mats)
  storage.mode(x) <- "numeric"
  list(x = x, prep = prep)
}

fer_env <- new.env(parent = baseenv())
sys.source(path_feriados, envir = fer_env)
feriados <- unique(as.IDate(fer_env$diasDesc))

features <- as.data.table(as.data.frame(
  arrow::open_dataset(path_features, format = "parquet") |>
    dplyr::filter(dia <= as.Date("2026-06-30")) |>
    dplyr::collect()
))
zl <- as.data.table(as.data.frame(
  arrow::open_dataset(path_zl, format = "parquet") |>
    dplyr::filter(dia <= as.Date("2026-06-30")) |>
    dplyr::collect()
))
segmento <- as.data.table(arrow::open_dataset(path_segmento, format = "parquet"))
admin <- as.data.table(arrow::open_dataset(path_admin, format = "parquet"))

for (dt in list(features, zl, segmento, admin)) {
  dt[, `:=`(
    version_cluster = as.character(version_cluster),
    cluster_id = as.character(cluster_id)
  )]
}
features[, dia := as.IDate(dia)]
zl[, dia := as.IDate(dia)]
version_cluster_obj <- unique(features$version_cluster)
if (length(version_cluster_obj) != 1L) stop("Se esperaba una version_cluster")

zl <- zl[
  hay_zl_visita_efectiva == TRUE & hay_zl_voluminosos != TRUE &
    !anio_mes %in% c(202508L, 202509L, 202601L, 202602L)
]
zl <- zl[, .(
  version_cluster, cluster_id, dia, hay_com,
  hay_zl_problema_comparable, hay_zl_limpio
)]
datos <- merge(
  features, zl,
  by = c("version_cluster", "cluster_id", "dia"),
  all = FALSE
)
datos <- segmento[datos, on = c("version_cluster", "cluster_id")]
datos <- admin[datos, on = c("version_cluster", "cluster_id")]

datos[, `:=`(
  target = as.integer(hay_zl_problema_comparable == TRUE),
  mes_calendario = as.integer(format(dia, "%m")),
  dia_semana = as.integer(format(dia, "%u")),
  fin_de_semana = as.integer(format(dia, "%u")) %in% c(6L, 7L),
  es_feriado = dia %in% feriados,
  vispera_feriado = (dia + 1L) %in% feriados
)]
datos[, dia_habil := !fin_de_semana & !es_feriado]
datos[, `:=`(
  exceso_min_tiempo_periodo_pred_pos = pmax(
    min_tiempo_desde_ultimo_levante_pred - min_levante_periodo, 0
  ),
  exceso_mean_tiempo_periodo_pred_pos = pmax(
    mean_tiempo_desde_ultimo_levante_pred - mean_levante_periodo, 0
  ),
  exceso_max_tiempo_periodo_pred_pos = pmax(
    max_tiempo_desde_ultimo_levante_pred - max_levante_periodo, 0
  )
)]
datos[, `:=`(
  exceso_min_tiempo_periodo_pred_trunc7 = pmin(exceso_min_tiempo_periodo_pred_pos, 7),
  exceso_mean_tiempo_periodo_pred_trunc7 = pmin(exceso_mean_tiempo_periodo_pred_pos, 7),
  exceso_max_tiempo_periodo_pred_trunc7 = pmin(exceso_max_tiempo_periodo_pred_pos, 7),
  ccz = as.character(ccz)
)]
datos <- asignar_split_congelado(datos)
datos <- datos[split %in% c("entrenamiento", "validacion")]
train <- datos[split == "entrenamiento"]
valid <- datos[split == "validacion"]
if (!nrow(train) || !nrow(valid)) stop("Train o validacion ZL vacios")

params <- list(
  objective = "binary:logistic", eval_metric = "logloss",
  max_depth = 4L, eta = 0.05, subsample = 0.85,
  colsample_bytree = 0.85, min_child_weight = 25,
  tree_method = "hist", nthread = 4L
)

predicciones <- list()
inventario <- list()
for (nombre in names(feature_sets)) {
  spec <- feature_sets[[nombre]]
  faltantes <- setdiff(c(spec$numericas, spec$categoricas), names(datos))
  if (length(faltantes)) stop("Faltan features ZL: ", paste(faltantes, collapse = ", "))
  mat_train <- preparar_matriz(train, spec$numericas, spec$categoricas)
  mat_valid <- preparar_matriz(
    valid, spec$numericas, spec$categoricas, prep = mat_train$prep
  )
  dtrain <- xgb.DMatrix(mat_train$x, label = train$target)
  dvalid <- xgb.DMatrix(mat_valid$x)
  set.seed(20260916L)
  fit <- xgb.train(params, dtrain, nrounds = 250L, verbose = 0)
  pred <- as.numeric(predict(fit, dvalid))
  predicciones[[nombre]] <- valid[, .(
    version_cluster, cluster_id, dia, split,
    target, hay_com, hay_zl_problema_comparable,
    municipio, ccz, nombre_barrio_ine,
    candidato = paste0("zl_", nombre), pred_prob = pred
  )]
  saveRDS(list(
    fit = fit, prep = mat_train$prep, spec = spec,
    params = params, nrounds = 250L,
    version_split = "reevaluacion_2026_v1"
  ), file.path(path_out, paste0("zl_", nombre, ".rds")))
  inventario[[nombre]] <- data.table(
    candidato = paste0("zl_", nombre), familia = "zona_limpia",
    algoritmo = "xgboost", filas_train = nrow(train),
    filas_validacion = nrow(valid), n_features_numericas = length(spec$numericas),
    n_features_categoricas = length(spec$categoricas),
    version_split = "reevaluacion_2026_v1",
    usa_test = FALSE, bootstrap = FALSE
  )
}

predicciones <- rbindlist(predicciones)
inventario <- rbindlist(inventario)
arrow::write_parquet(
  predicciones, file.path(path_out, "predicciones_validacion.parquet"),
  compression = "zstd"
)
fwrite(inventario, file.path(path_out, "inventario.csv"))
print(inventario)
