library(arrow)
library(data.table)

source("zona_limpia/funciones_zona_limpia.R")

path_comparacion_zl <- "data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia"
out_processed <- "data/processed/zona_limpia"
out_outputs <- "zona_limpia/outputs"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)

modelos <- data.table::data.table(
  modelo_id = c(
    "logistico_completo",
    "logistico_reducido",
    "logistico_reducido_d2",
    "random_forest",
    "xgboost"
  ),
  path_predicciones = c(
    "data/processed/modelos/logistico_cluster_dia/predicciones",
    "data/processed/modelos/logistico_cluster_dia_reducido/predicciones_validacion",
    "data/processed/modelos/logistico_cluster_dia_reducido_reclamos_d2/predicciones_validacion",
    "data/processed/modelos/random_forest_cluster_dia/predicciones",
    "data/processed/modelos/xgboost_cluster_dia/predicciones"
  )
)

dir.create(out_processed, recursive = TRUE, showWarnings = FALSE)
dir.create(out_outputs, recursive = TRUE, showWarnings = FALSE)

leer_predicciones_modelo <- function(modelo_id, path_predicciones) {
  if (!dir.exists(path_predicciones)) {
    warning("No existe path de predicciones para ", modelo_id, ": ", path_predicciones)
    return(data.table::data.table())
  }

  pred <- as.data.table(arrow::open_dataset(path_predicciones, format = "parquet"))
  cols_req <- c("cluster_id", "dia", "pred_prob", "version_cluster")
  if (!all(cols_req %in% names(pred))) {
    stop("Predicciones de ", modelo_id, " deben tener columnas: ", paste(cols_req, collapse = ", "))
  }

  if (!is.na(target_version_cluster) && target_version_cluster != "") {
    pred <- pred[version_cluster == target_version_cluster]
  }

  if (nrow(pred) == 0L) {
    return(data.table::data.table())
  }

  pred[, modelo_id := modelo_id]
  if (!"split" %in% names(pred)) pred[, split := NA_character_]
  pred[, cluster_id := as.character(cluster_id)]
  pred[, dia := as.IDate(dia)]
  pred[, version_cluster := as.character(version_cluster)]

  pred <- pred[, .(
    modelo_id,
    split,
    version_cluster,
    cluster_id,
    dia,
    anio_mes = as.integer(format(dia, "%Y%m")),
    pred_prob,
    target_com = if ("target" %in% names(pred)) target else NA_integer_,
    n_reclamos_com_pred = if ("n_reclamos" %in% names(pred)) n_reclamos else NA_integer_
  )]

  pred[
    ,
    ranking_dia := frank(-pred_prob, ties.method = "first"),
    by = .(modelo_id, dia)
  ]
  pred[
    ,
    n_scores_dia := .N,
    by = .(modelo_id, dia)
  ]
  pred[, percentil_score_dia := ranking_dia / n_scores_dia]
  pred[, top_1 := percentil_score_dia <= 0.01]
  pred[, top_5 := percentil_score_dia <= 0.05]
  pred[, top_10 := percentil_score_dia <= 0.10]
  pred[, top_20 := percentil_score_dia <= 0.20]

  pred[]
}

predicciones <- data.table::rbindlist(
  lapply(seq_len(nrow(modelos)), function(i) {
    leer_predicciones_modelo(modelos$modelo_id[i], modelos$path_predicciones[i])
  }),
  fill = TRUE
)

if (nrow(predicciones) == 0L) {
  stop("No se encontraron predicciones disponibles.")
}

if (is.na(target_version_cluster) || target_version_cluster == "") {
  versiones <- sort(unique(predicciones$version_cluster))
  target_version_cluster <- versiones[length(versiones)]
  predicciones <- predicciones[version_cluster == target_version_cluster]
}

comparacion_zl <- as.data.table(arrow::open_dataset(path_comparacion_zl, format = "parquet"))
comparacion_zl[, cluster_id := as.character(cluster_id)]
comparacion_zl[, dia := as.IDate(dia)]
comparacion_zl[, version_cluster := as.character(version_cluster)]
comparacion_zl <- comparacion_zl[version_cluster == target_version_cluster]
comparacion_zl <- filtrar_periodo_analisis_zona_limpia(comparacion_zl)

cols_zl <- c(
  "cluster_id",
  "dia",
  "estado_comparacion",
  "universo_comparable_zl",
  "hay_com",
  "hay_zl_visita_efectiva",
  "hay_zl_problema_comparable",
  "hay_zl_limpio",
  "hay_zl_voluminosos",
  "n_reclamos",
  "n_zl",
  "n_zl_visitas_efectivas",
  "n_zl_problema_comparable",
  "n_zl_limpio",
  "n_zl_voluminosos"
)
faltantes_zl <- setdiff(cols_zl, names(comparacion_zl))
if (length(faltantes_zl) > 0L) {
  stop("Faltan columnas en comparacion ZL: ", paste(faltantes_zl, collapse = ", "))
}

comparacion_zl <- comparacion_zl[, ..cols_zl]

score_zl <- comparacion_zl[
  predicciones,
  on = .(cluster_id, dia),
  nomatch = 0
]

score_zl[, tipo_evento_zl := data.table::fcase(
  estado_comparacion == "solo_zona_limpia_problema",
  "zl_problema_sin_com",
  estado_comparacion == "ambos_reportan_problema",
  "zl_problema_con_com",
  estado_comparacion == "solo_com_zl_limpio",
  "com_zl_limpio",
  estado_comparacion == "ambos_sin_problema_observado",
  "zl_limpio_sin_com",
  estado_comparacion == "solo_zona_limpia_voluminosos",
  "zl_voluminosos_sin_com",
  estado_comparacion == "com_y_zl_voluminosos",
  "com_zl_voluminosos",
  default = "fuera_universo_comparable"
)]

score_zl_comparable <- score_zl[universo_comparable_zl == TRUE]

resumen_modelo_periodo <- score_zl[
  ,
  .(
    filas_score_zl = .N,
    dias = data.table::uniqueN(dia),
    dia_min = min(dia),
    dia_max = max(dia),
    clusters = data.table::uniqueN(cluster_id),
    filas_universo_comparable = sum(universo_comparable_zl == TRUE),
    filas_solo_zl_problema = sum(estado_comparacion == "solo_zona_limpia_problema")
  ),
  by = .(modelo_id, split)
][order(modelo_id, split)]

resumen_estado <- score_zl_comparable[
  ,
  .(
    n_cluster_dia = .N,
    n_com = sum(n_reclamos),
    n_zl = sum(n_zl),
    score_media = mean(pred_prob, na.rm = TRUE),
    score_mediana = stats::median(pred_prob, na.rm = TRUE),
    score_p75 = as.numeric(stats::quantile(pred_prob, 0.75, na.rm = TRUE)),
    score_p90 = as.numeric(stats::quantile(pred_prob, 0.90, na.rm = TRUE)),
    n_top_1 = sum(top_1),
    n_top_5 = sum(top_5),
    n_top_10 = sum(top_10),
    n_top_20 = sum(top_20),
    pct_top_1 = mean(top_1),
    pct_top_5 = mean(top_5),
    pct_top_10 = mean(top_10),
    pct_top_20 = mean(top_20)
  ),
  by = .(modelo_id, split, estado_comparacion, tipo_evento_zl)
][order(modelo_id, split, tipo_evento_zl)]

resumen_solo_zl_problema <- score_zl_comparable[
  estado_comparacion == "solo_zona_limpia_problema",
  .(
    n_cluster_dia = .N,
    dias = data.table::uniqueN(dia),
    clusters = data.table::uniqueN(cluster_id),
    score_media = mean(pred_prob, na.rm = TRUE),
    score_mediana = stats::median(pred_prob, na.rm = TRUE),
    score_p75 = as.numeric(stats::quantile(pred_prob, 0.75, na.rm = TRUE)),
    score_p90 = as.numeric(stats::quantile(pred_prob, 0.90, na.rm = TRUE)),
    n_top_1 = sum(top_1),
    n_top_5 = sum(top_5),
    n_top_10 = sum(top_10),
    n_top_20 = sum(top_20),
    pct_top_1 = mean(top_1),
    pct_top_5 = mean(top_5),
    pct_top_10 = mean(top_10),
    pct_top_20 = mean(top_20),
    problemas_zl = sum(n_zl_problema_comparable)
  ),
  by = .(modelo_id, split)
][order(modelo_id, split)]

captura_top_por_estado <- data.table::rbindlist(list(
  score_zl_comparable[, .(top_pct = 0.01, en_top = top_1), by = .(modelo_id, split, estado_comparacion, tipo_evento_zl, cluster_id, dia)],
  score_zl_comparable[, .(top_pct = 0.05, en_top = top_5), by = .(modelo_id, split, estado_comparacion, tipo_evento_zl, cluster_id, dia)],
  score_zl_comparable[, .(top_pct = 0.10, en_top = top_10), by = .(modelo_id, split, estado_comparacion, tipo_evento_zl, cluster_id, dia)],
  score_zl_comparable[, .(top_pct = 0.20, en_top = top_20), by = .(modelo_id, split, estado_comparacion, tipo_evento_zl, cluster_id, dia)]
), fill = TRUE)

captura_top_por_estado <- captura_top_por_estado[
  ,
  .(
    n_cluster_dia = .N,
    n_en_top = sum(en_top),
    pct_en_top = mean(en_top)
  ),
  by = .(modelo_id, split, estado_comparacion, tipo_evento_zl, top_pct)
][order(modelo_id, split, tipo_evento_zl, top_pct)]

decil_solo_zl <- score_zl_comparable[
  estado_comparacion == "solo_zona_limpia_problema"
]
decil_solo_zl[
  ,
  decil_score := pmin(10L, pmax(1L, ceiling(percentil_score_dia * 10))),
  by = .(modelo_id, dia)
]
decil_solo_zl <- decil_solo_zl[
  ,
  .(
    n_cluster_dia = .N,
    problemas_zl = sum(n_zl_problema_comparable),
    score_media = mean(pred_prob, na.rm = TRUE)
  ),
  by = .(modelo_id, split, decil_score)
][order(modelo_id, split, decil_score)]

score_zl[, anio := as.integer(format(dia, "%Y"))]

arrow::write_dataset(
  score_zl,
  path = file.path(out_processed, "scores_com_vs_zona_limpia_cluster_dia"),
  format = "parquet",
  partitioning = c("version_cluster", "modelo_id", "anio", "anio_mes"),
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

data.table::fwrite(
  resumen_modelo_periodo,
  file.path(out_outputs, "scores_com_vs_zona_limpia_resumen_modelo_periodo.csv")
)
data.table::fwrite(
  resumen_estado,
  file.path(out_outputs, "scores_com_vs_zona_limpia_resumen_estado.csv")
)
data.table::fwrite(
  resumen_solo_zl_problema,
  file.path(out_outputs, "scores_com_vs_zona_limpia_resumen_solo_zl_problema.csv")
)
data.table::fwrite(
  captura_top_por_estado,
  file.path(out_outputs, "scores_com_vs_zona_limpia_captura_top_por_estado.csv")
)
data.table::fwrite(
  decil_solo_zl,
  file.path(out_outputs, "scores_com_vs_zona_limpia_decil_solo_zl_problema.csv")
)

print(resumen_modelo_periodo)
print(resumen_solo_zl_problema)
