library(arrow)
library(data.table)

source("funciones/modelos_utils.R")

path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_comparacion_zl <- "data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia"
path_modelo <- "data/processed/modelos/logistico_cluster_dia_reducido_reclamos_d2/modelo_logistico_reducido.rds"
out_outputs <- "zona_limpia/outputs"

modelo_id <- "logistico_reducido_d2"
meses_analisis <- c(202603L, 202604L, 202605L)
rezago_reclamos_dias <- 2L
target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)

dir.create(out_outputs, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(path_modelo)) {
  stop("No existe el modelo entrenado: ", path_modelo)
}

modelo <- readRDS(path_modelo)

if (is.na(target_version_cluster) || target_version_cluster == "") {
  target_version_cluster <- modelo$version_cluster
}

features_modelo <- modelo$features_modelo
prep_modelo <- modelo$prep
coef_pred <- modelo$coeficientes_prediccion

if (is.null(features_modelo) || is.null(prep_modelo) || is.null(coef_pred)) {
  stop("El objeto de modelo no contiene features_modelo, prep o coeficientes_prediccion.")
}

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

datos <- as.data.table(arrow::open_dataset(path_features, format = "parquet"))
datos[, version_cluster := as.character(version_cluster)]
datos <- datos[
  version_cluster == target_version_cluster &
    anio_mes %in% meses_analisis
]

faltantes <- setdiff(
  c(features_base_requeridas, "cluster_id", "dia", "anio_mes", "version_cluster"),
  names(datos)
)
if (length(faltantes) > 0L) {
  stop("Faltan columnas para aplicar el modelo: ", paste(faltantes, collapse = ", "))
}

datos[, cluster_id := as.character(cluster_id)]
datos[, dia := as.IDate(dia)]

datos <- aplicar_rezago_historia_reclamos(
  datos,
  rezago_reclamos_dias = rezago_reclamos_dias
)
datos <- agregar_features_logistico_reducido(datos)

mat_pred <- preparar_matriz(datos, features_modelo, prep = prep_modelo)
x_pred <- cbind(intercept = 1, mat_pred$x)

coef_pred[is.na(coef_pred)] <- 0
coef_pred <- coef_pred[colnames(x_pred)]
if (anyNA(coef_pred)) {
  stop("No coinciden los coeficientes del modelo con la matriz de prediccion.")
}

predicciones <- datos[, .(
  cluster_id,
  dia,
  anio_mes,
  version_cluster
)]
predicciones[, `:=`(
  modelo_id = modelo_id,
  pred_prob = as.numeric(plogis(x_pred %*% coef_pred))
)]

predicciones[
  ,
  ranking_dia := frank(-pred_prob, ties.method = "first"),
  by = dia
]
predicciones[, n_scores_dia := .N, by = dia]

comparacion_zl <- as.data.table(arrow::open_dataset(path_comparacion_zl, format = "parquet"))
comparacion_zl[, cluster_id := as.character(cluster_id)]
comparacion_zl[, dia := as.IDate(dia)]
comparacion_zl[, version_cluster := as.character(version_cluster)]
comparacion_zl <- comparacion_zl[
  version_cluster == target_version_cluster &
    anio_mes %in% meses_analisis
]

cols_zl <- c(
  "cluster_id",
  "dia",
  "hay_com",
  "hay_zl_visita_efectiva",
  "hay_zl_problema_comparable",
  "hay_zl_voluminosos",
  "n_reclamos",
  "n_zl",
  "n_zl_visitas_efectivas",
  "n_zl_problema_comparable",
  "n_zl_voluminosos"
)
faltantes_zl <- setdiff(cols_zl, names(comparacion_zl))
if (length(faltantes_zl) > 0L) {
  stop("Faltan columnas en comparacion ZL: ", paste(faltantes_zl, collapse = ", "))
}

comparacion_zl <- comparacion_zl[, ..cols_zl]

eval_diaria <- comparacion_zl[
  predicciones,
  on = .(cluster_id, dia)
]

cols_logicas <- c(
  "hay_com",
  "hay_zl_visita_efectiva",
  "hay_zl_problema_comparable",
  "hay_zl_voluminosos"
)
for (col in cols_logicas) {
  eval_diaria[is.na(get(col)), (col) := FALSE]
}

cols_conteo <- c(
  "n_reclamos",
  "n_zl",
  "n_zl_visitas_efectivas",
  "n_zl_problema_comparable",
  "n_zl_voluminosos"
)
for (col in cols_conteo) {
  eval_diaria[is.na(get(col)), (col) := 0L]
}

eval_diaria[, problema_real_observado := hay_com | hay_zl_problema_comparable]
eval_diaria[, visita_efectiva_zl := hay_zl_visita_efectiva]

n_visitas_dia <- eval_diaria[
  visita_efectiva_zl == TRUE,
  .(n_visitas_zl = .N),
  by = dia
]

eval_diaria <- n_visitas_dia[
  eval_diaria,
  on = "dia"
]
eval_diaria[is.na(n_visitas_zl), n_visitas_zl := 0L]
eval_diaria[, seleccionado_modelo_igual_n_zl := ranking_dia <= n_visitas_zl]

resumen_diario <- eval_diaria[
  ,
  .(
    anio_mes = unique(anio_mes),
    modelo_id = unique(modelo_id),
    version_cluster = unique(version_cluster),
    n_scores_dia = unique(n_scores_dia),
    n_visitas_zl = unique(n_visitas_zl),
    n_zl_registros_en_visitas = sum(n_zl[visita_efectiva_zl == TRUE]),
    n_zl_visitas_efectivas_registros = sum(n_zl_visitas_efectivas),
    n_zl_con_problema_comparable = sum(visita_efectiva_zl & hay_zl_problema_comparable),
    n_zl_con_com = sum(visita_efectiva_zl & hay_com),
    n_zl_con_problema_real = sum(visita_efectiva_zl & problema_real_observado),
    n_zl_con_voluminosos_no_contado = sum(visita_efectiva_zl & hay_zl_voluminosos),
    n_modelo_top = sum(seleccionado_modelo_igual_n_zl),
    n_modelo_top_con_zl_problema_observado = sum(
      seleccionado_modelo_igual_n_zl & hay_zl_problema_comparable
    ),
    n_modelo_top_con_com = sum(seleccionado_modelo_igual_n_zl & hay_com),
    n_modelo_top_con_problema_real_observado = sum(
      seleccionado_modelo_igual_n_zl & problema_real_observado
    ),
    n_modelo_top_con_voluminosos_no_contado = sum(
      seleccionado_modelo_igual_n_zl & hay_zl_voluminosos
    ),
    n_reclamos_com_observados_dia = sum(hay_com),
    n_problemas_reales_observados_dia = sum(problema_real_observado),
    n_interseccion_zl_modelo = sum(visita_efectiva_zl & seleccionado_modelo_igual_n_zl),
    score_min_top_modelo = if (any(seleccionado_modelo_igual_n_zl)) {
      min(pred_prob[seleccionado_modelo_igual_n_zl], na.rm = TRUE)
    } else {
      NA_real_
    },
    score_medio_top_modelo = if (any(seleccionado_modelo_igual_n_zl)) {
      mean(pred_prob[seleccionado_modelo_igual_n_zl], na.rm = TRUE)
    } else {
      NA_real_
    }
  ),
  by = dia
][order(dia)]

resumen_diario[, tasa_zl_problema_real := fifelse(
  n_visitas_zl > 0,
  n_zl_con_problema_real / n_visitas_zl,
  NA_real_
)]
resumen_diario[, tasa_zl_com := fifelse(
  n_visitas_zl > 0,
  n_zl_con_com / n_visitas_zl,
  NA_real_
)]
resumen_diario[, tasa_modelo_problema_real_observado := fifelse(
  n_modelo_top > 0,
  n_modelo_top_con_problema_real_observado / n_modelo_top,
  NA_real_
)]
resumen_diario[, tasa_modelo_com := fifelse(
  n_modelo_top > 0,
  n_modelo_top_con_com / n_modelo_top,
  NA_real_
)]
resumen_diario[, diferencia_n_problemas_modelo_vs_zl :=
  n_modelo_top_con_problema_real_observado - n_zl_con_problema_real]
resumen_diario[, diferencia_n_com_modelo_vs_zl :=
  n_modelo_top_con_com - n_zl_con_com]
resumen_diario[, diferencia_tasa_modelo_vs_zl :=
  tasa_modelo_problema_real_observado - tasa_zl_problema_real]
resumen_diario[, diferencia_tasa_com_modelo_vs_zl :=
  tasa_modelo_com - tasa_zl_com]
resumen_diario[, ratio_tasa_modelo_vs_zl := fifelse(
  tasa_zl_problema_real > 0,
  tasa_modelo_problema_real_observado / tasa_zl_problema_real,
  NA_real_
)]
resumen_diario[, ratio_tasa_com_modelo_vs_zl := fifelse(
  tasa_zl_com > 0,
  tasa_modelo_com / tasa_zl_com,
  NA_real_
)]
resumen_diario[, capture_rate_zl_com := fifelse(
  n_reclamos_com_observados_dia > 0,
  n_zl_con_com / n_reclamos_com_observados_dia,
  NA_real_
)]
resumen_diario[, capture_rate_modelo_com := fifelse(
  n_reclamos_com_observados_dia > 0,
  n_modelo_top_con_com / n_reclamos_com_observados_dia,
  NA_real_
)]
resumen_diario[, capture_rate_zl_problemas_observados := fifelse(
  n_problemas_reales_observados_dia > 0,
  n_zl_con_problema_real / n_problemas_reales_observados_dia,
  NA_real_
)]
resumen_diario[, capture_rate_modelo_problemas_observados := fifelse(
  n_problemas_reales_observados_dia > 0,
  n_modelo_top_con_problema_real_observado / n_problemas_reales_observados_dia,
  NA_real_
)]
resumen_diario[, pct_visitas_zl_en_top_modelo := fifelse(
  n_visitas_zl > 0,
  n_interseccion_zl_modelo / n_visitas_zl,
  NA_real_
)]

resumen_mensual <- resumen_diario[
  ,
  .(
    dias = .N,
    n_scores_dia_promedio = mean(n_scores_dia),
    n_visitas_zl_total = sum(n_visitas_zl),
    n_visitas_zl_promedio = mean(n_visitas_zl),
    n_zl_con_problema_real_total = sum(n_zl_con_problema_real),
    n_modelo_top_con_problema_real_observado_total = sum(
      n_modelo_top_con_problema_real_observado
    ),
    n_zl_con_com_total = sum(n_zl_con_com),
    n_modelo_top_con_com_total = sum(n_modelo_top_con_com),
    n_reclamos_com_observados_total = sum(n_reclamos_com_observados_dia),
    tasa_zl_problema_real_agregada = sum(n_zl_con_problema_real) / sum(n_visitas_zl),
    tasa_modelo_problema_real_observado_agregada =
      sum(n_modelo_top_con_problema_real_observado) / sum(n_modelo_top),
    tasa_zl_com_agregada = sum(n_zl_con_com) / sum(n_visitas_zl),
    tasa_modelo_com_agregada = sum(n_modelo_top_con_com) / sum(n_modelo_top),
    diferencia_n_problemas_modelo_vs_zl_total = sum(diferencia_n_problemas_modelo_vs_zl),
    diferencia_n_com_modelo_vs_zl_total = sum(diferencia_n_com_modelo_vs_zl),
    diferencia_tasa_modelo_vs_zl_agregada =
      (sum(n_modelo_top_con_problema_real_observado) / sum(n_modelo_top)) -
        (sum(n_zl_con_problema_real) / sum(n_visitas_zl)),
    diferencia_tasa_com_modelo_vs_zl_agregada =
      (sum(n_modelo_top_con_com) / sum(n_modelo_top)) -
        (sum(n_zl_con_com) / sum(n_visitas_zl)),
    ratio_tasa_modelo_vs_zl_agregado =
      (sum(n_modelo_top_con_problema_real_observado) / sum(n_modelo_top)) /
        (sum(n_zl_con_problema_real) / sum(n_visitas_zl)),
    ratio_tasa_com_modelo_vs_zl_agregado =
      (sum(n_modelo_top_con_com) / sum(n_modelo_top)) /
        (sum(n_zl_con_com) / sum(n_visitas_zl)),
    capture_rate_zl_com_agregado = sum(n_zl_con_com) / sum(n_reclamos_com_observados_dia),
    capture_rate_modelo_com_agregado =
      sum(n_modelo_top_con_com) / sum(n_reclamos_com_observados_dia),
    n_interseccion_zl_modelo_total = sum(n_interseccion_zl_modelo),
    pct_visitas_zl_en_top_modelo_agregado =
      sum(n_interseccion_zl_modelo) / sum(n_visitas_zl)
  ),
  by = .(anio_mes, modelo_id, version_cluster)
][order(anio_mes)]

data.table::fwrite(
  resumen_diario,
  file.path(out_outputs, "seleccion_zl_vs_modelo_diario_logistico_reducido_d2.csv")
)
data.table::fwrite(
  resumen_mensual,
  file.path(out_outputs, "seleccion_zl_vs_modelo_mensual_logistico_reducido_d2.csv")
)

print(resumen_diario)
print(resumen_mensual)
