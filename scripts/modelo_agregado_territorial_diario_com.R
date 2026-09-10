library(arrow)
library(data.table)
library(mgcv)

path_pred <- "app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia/modelo_id=com_reclamo"
path_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
path_segmento <- "data/processed/cluster_territorial/cluster_segmento_censal"
path_modelo_com <- "data/processed/modelos/logistico_cluster_dia_reducido_reclamos_d2/modelo_logistico_reducido.rds"
out_base <- "outputs/modelos_agregados_territoriales_com"

dir.create(out_base, recursive = TRUE, showWarnings = FALSE)

paths_req <- c(path_pred, path_admin, path_segmento, path_modelo_com)
if (any(!file.exists(paths_req) & !dir.exists(paths_req))) {
  stop("Faltan insumos: ", paste(paths_req[!file.exists(paths_req) & !dir.exists(paths_req)], collapse = ", "))
}

modelo_com <- readRDS(path_modelo_com)

cols_pred <- c(
  "cluster_id", "dia_objetivo", "version_cluster", "pred_prob",
  "tuvo_reclamo_observado", "n_reclamos_observado",
  "n_reclamos_lag1", "n_reclamos_sum_7d", "n_reclamos_sum_30d",
  "mean_tiempo_desde_ultimo_levante_pred", "n_contenedores_activos",
  "pct_contenedores_inferidos"
)

pred <- as.data.table(as.data.frame(
  arrow::open_dataset(path_pred) |>
    dplyr::select(dplyr::all_of(cols_pred)) |>
    dplyr::collect()
))

pred[, dia_objetivo := as.IDate(dia_objetivo)]
pred <- pred[!is.na(tuvo_reclamo_observado)]

version_cluster_obj <- unique(pred$version_cluster)
if (length(version_cluster_obj) != 1L) {
  stop("Se esperaba una version_cluster; hay: ", paste(version_cluster_obj, collapse = ", "))
}

admin <- as.data.table(as.data.frame(arrow::open_dataset(path_admin)))
segmento <- as.data.table(as.data.frame(arrow::open_dataset(path_segmento)))
admin <- admin[version_cluster == version_cluster_obj]
segmento <- segmento[version_cluster == version_cluster_obj]

if (anyDuplicated(admin$cluster_id)) stop("cluster_id duplicado en admin")
if (anyDuplicated(segmento$cluster_id)) stop("cluster_id duplicado en segmento")

geo <- admin[
  ,
  .(
    cluster_id,
    barrio = nombre_barrio_ine,
    ccz = as.character(ccz),
    densidad_pob_barrio = densidad_pob_barrio_2023_km2,
    densidad_pob_ccz = densidad_pob_ccz_2023_km2
  )
][
  segmento[
    ,
    .(
      cluster_id,
      porc_nbi_segmento,
      porc_asentamiento_nbi_segmento,
      porc_vivienda_inadecuada_segmento,
      densidad_pob_segmento = densidad_pob_km2
    )
  ],
  on = "cluster_id"
]

pred <- geo[pred, on = "cluster_id"]
pred[is.na(barrio) | !nzchar(barrio), barrio := "SIN_BARRIO"]
pred[is.na(ccz) | !nzchar(ccz), ccz := "SIN_CCZ"]

q_seguro <- function(x, p) {
  if (all(is.na(x))) return(NA_real_)
  as.numeric(quantile(x, probs = p, na.rm = TRUE, type = 8))
}

construir_base_territorio <- function(dt, nivel = c("barrio", "ccz")) {
  nivel <- match.arg(nivel)
  densidad_col <- if (nivel == "barrio") "densidad_pob_barrio" else "densidad_pob_ccz"

  base <- dt[
    ,
    .(
      n_clusters = .N,
      clusters_con_reclamo = sum(tuvo_reclamo_observado == 1L),
      n_reclamos = sum(n_reclamos_observado, na.rm = TRUE),
      suma_scores = sum(pred_prob, na.rm = TRUE),
      score_medio = mean(pred_prob, na.rm = TRUE),
      score_sd = sd(pred_prob, na.rm = TRUE),
      score_p90 = q_seguro(pred_prob, 0.90),
      tiempo_levante_medio = mean(mean_tiempo_desde_ultimo_levante_pred, na.rm = TRUE),
      tiempo_levante_p90 = q_seguro(mean_tiempo_desde_ultimo_levante_pred, 0.90),
      pct_clusters_tiempo_3omas = mean(mean_tiempo_desde_ultimo_levante_pred >= 3, na.rm = TRUE),
      contenedores_activos_medio = mean(n_contenedores_activos, na.rm = TRUE),
      pct_inferidos_medio = mean(pct_contenedores_inferidos, na.rm = TRUE),
      reclamos_lag1_medio = mean(n_reclamos_lag1, na.rm = TRUE),
      reclamos_7d_medio = mean(n_reclamos_sum_7d, na.rm = TRUE),
      reclamos_30d_medio = mean(n_reclamos_sum_30d, na.rm = TRUE),
      nbi_medio = mean(porc_nbi_segmento, na.rm = TRUE),
      asentamiento_medio = mean(porc_asentamiento_nbi_segmento, na.rm = TRUE),
      vivienda_inadecuada_media = mean(porc_vivienda_inadecuada_segmento, na.rm = TRUE),
      densidad_pob = mean(get(densidad_col), na.rm = TRUE)
    ),
    by = c("dia_objetivo", nivel)
  ]

  setnames(base, nivel, "territorio")
  base[, territorio := as.factor(territorio)]
  base[, anio_mes := year(dia_objetivo) * 100L + month(dia_objetivo)]
  base[
    , split_modelo := fcase(
      anio_mes %in% modelo_com$meses_train, "entrenamiento",
      anio_mes %in% modelo_com$meses_validacion, "validacion",
      anio_mes %in% modelo_com$meses_test, "test",
      default = "fuera_split"
    )
  ]
  base[, dia_semana := factor(weekdays(dia_objetivo))]
  base[, mes := factor(month(dia_objetivo))]
  base[, prop_clusters_reclamo := clusters_con_reclamo / n_clusters]
  base[, nivel_territorial := nivel]
  base[]
}

features_continuas <- c(
  "score_medio", "score_sd", "score_p90",
  "tiempo_levante_medio", "tiempo_levante_p90", "pct_clusters_tiempo_3omas",
  "contenedores_activos_medio", "pct_inferidos_medio",
  "reclamos_lag1_medio", "reclamos_7d_medio", "reclamos_30d_medio",
  "nbi_medio", "asentamiento_medio", "vivienda_inadecuada_media",
  "densidad_pob"
)

preparar_features <- function(base) {
  train <- base[split_modelo == "entrenamiento"]
  prep <- rbindlist(lapply(features_continuas, function(v) {
    x <- train[[v]]
    x[!is.finite(x)] <- NA_real_
    mediana <- median(x, na.rm = TRUE)
    x[is.na(x)] <- mediana
    desvio <- sd(x)
    if (!is.finite(desvio) || desvio == 0) desvio <- 1
    data.table(variable = v, mediana = mediana, media = mean(x), desvio = desvio)
  }))

  for (i in seq_len(nrow(prep))) {
    v <- prep$variable[[i]]
    z <- paste0("z_", v)
    x <- as.numeric(base[[v]])
    x[!is.finite(x)] <- NA_real_
    x[is.na(x)] <- prep$mediana[[i]]
    base[, (z) := (x - prep$media[[i]]) / prep$desvio[[i]]]
  }
  list(base = base, prep = prep)
}

formula_modelo <- prop_clusters_reclamo ~ dia_semana + mes +
  z_score_medio + z_score_sd + z_score_p90 +
  z_tiempo_levante_medio + z_tiempo_levante_p90 + z_pct_clusters_tiempo_3omas +
  z_contenedores_activos_medio + z_pct_inferidos_medio +
  z_reclamos_lag1_medio + z_reclamos_7d_medio + z_reclamos_30d_medio +
  z_nbi_medio + z_asentamiento_medio + z_vivienda_inadecuada_media +
  z_densidad_pob +
  z_tiempo_levante_medio:z_nbi_medio +
  z_score_medio:z_nbi_medio +
  s(territorio, bs = "re")

ajustar_nivel <- function(base, nivel) {
  prep_obj <- preparar_features(copy(base))
  base <- prep_obj$base
  train <- base[split_modelo == "entrenamiento"]

  fit <- bam(
    formula_modelo,
    data = train,
    family = binomial(),
    weights = n_clusters,
    method = "fREML",
    discrete = TRUE,
    nthreads = 2L
  )

  newdata_pred <- as.data.frame(
    base[, setdiff(names(base), "dia_objetivo"), with = FALSE]
  )

  base[, pred_prob_territorial := as.numeric(mgcv::predict.gam(
    fit,
    newdata = newdata_pred,
    type = "response"
  ))]
  base[, clusters_esperados_territorial := n_clusters * pred_prob_territorial]

  pred_dia <- base[
    ,
    .(
      clusters_observados = sum(clusters_con_reclamo),
      clusters_esperados_territorial = sum(clusters_esperados_territorial),
      clusters_esperados_suma_scores = sum(suma_scores),
      n_clusters = sum(n_clusters)
    ),
    by = .(dia_objetivo, split_modelo, nivel_territorial)
  ]

  diag <- data.table(
    nivel_territorial = nivel,
    n_territorios = nlevels(base$territorio),
    filas_train = nrow(train),
    singular = NA,
    convergencia = if (isTRUE(fit$converged)) "OK" else "REVISAR",
    AIC = AIC(fit),
    logLik = as.numeric(logLik(fit))
  )
  if (!nzchar(diag$convergencia)) diag[, convergencia := "OK"]

  list(base = base, fit = fit, prep = prep_obj$prep, pred_dia = pred_dia, diagnostico = diag)
}

metricas_diarias <- function(pred_dia, media_train) {
  rbindlist(lapply(c("validacion", "test", "validacion + test"), function(periodo) {
    dt <- if (periodo == "validacion + test") {
      pred_dia[split_modelo %in% c("validacion", "test")]
    } else {
      pred_dia[split_modelo == periodo]
    }

    y <- dt$clusters_observados
    pred_modelo <- dt$clusters_esperados_territorial
    pred_scores <- dt$clusters_esperados_suma_scores
    pred_media <- rep(media_train, length(y))

    rbindlist(list(
      data.table(modelo = "territorial_jerarquico_intercepto", pred = pred_modelo),
      data.table(modelo = "suma_scores_cluster", pred = pred_scores),
      data.table(modelo = "promedio_train", pred = pred_media)
    ))[
      ,
      .(
        dias = length(y),
        media_observada = mean(y),
        media_predicha = mean(pred),
        sesgo = mean(pred - y),
        mae = mean(abs(pred - y)),
        rmse = sqrt(mean((pred - y)^2)),
        correlacion = if (sd(pred) > 0) cor(pred, y) else NA_real_,
        sd_observado = sd(y),
        sd_predicho = sd(pred),
        razon_sd = sd(pred) / sd(y)
      ),
      by = modelo
    ][, periodo := periodo][]
  }))
}

base_barrio <- construir_base_territorio(pred, "barrio")
base_ccz <- construir_base_territorio(pred, "ccz")

res_barrio <- ajustar_nivel(base_barrio, "barrio")
res_ccz <- ajustar_nivel(base_ccz, "ccz")

media_train_ciudad <- pred[
  (year(dia_objetivo) * 100L + month(dia_objetivo)) %in% modelo_com$meses_train,
  .(clusters = sum(tuvo_reclamo_observado == 1L)),
  by = dia_objetivo
][, mean(clusters)]

metricas <- rbindlist(list(
  metricas_diarias(res_barrio$pred_dia, media_train_ciudad)[, nivel_territorial := "barrio"],
  metricas_diarias(res_ccz$pred_dia, media_train_ciudad)[, nivel_territorial := "ccz"]
), fill = TRUE)

diagnostico <- rbindlist(list(res_barrio$diagnostico, res_ccz$diagnostico), fill = TRUE)
predicciones_diarias <- rbindlist(list(res_barrio$pred_dia, res_ccz$pred_dia), fill = TRUE)
base_modelo <- rbindlist(list(res_barrio$base, res_ccz$base), fill = TRUE)
prep <- rbindlist(list(
  res_barrio$prep[, nivel_territorial := "barrio"],
  res_ccz$prep[, nivel_territorial := "ccz"]
), fill = TRUE)

fwrite(metricas, file.path(out_base, "metricas_diarias.csv"))
fwrite(diagnostico, file.path(out_base, "diagnostico_modelos.csv"))
fwrite(predicciones_diarias, file.path(out_base, "predicciones_diarias.csv"))
fwrite(base_modelo, file.path(out_base, "base_territorio_dia.csv"))
fwrite(prep, file.path(out_base, "preparacion_features.csv"))
saveRDS(res_barrio$fit, file.path(out_base, "modelo_barrio_dia_bam.rds"))
saveRDS(res_ccz$fit, file.path(out_base, "modelo_ccz_dia_bam.rds"))

coef_fijos <- rbindlist(list(
  data.table(
    nivel_territorial = "barrio",
    variable = names(coef(res_barrio$fit)),
    coeficiente = unname(coef(res_barrio$fit))
  ),
  data.table(
    nivel_territorial = "ccz",
    variable = names(coef(res_ccz$fit)),
    coeficiente = unname(coef(res_ccz$fit))
  )
), fill = TRUE)
fwrite(coef_fijos, file.path(out_base, "coeficientes_fijos.csv"))

print(diagnostico)
print(metricas[periodo == "validacion + test"])
