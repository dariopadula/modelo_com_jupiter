library(arrow)
library(data.table)
library(mgcv)

path_pred <- "app_operativa_v2/data/operacional/predicciones_operativas_cluster_dia/modelo_id=com_reclamo"
path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
path_segmento <- "data/processed/cluster_territorial/cluster_segmento_censal"
path_modelo_com <- "data/processed/modelos/logistico_cluster_dia_reducido_reclamos_d2/modelo_logistico_reducido.rds"
out_base <- "outputs/experimento_modelos_agregados_m0_m4_com"

dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
modelo_com <- readRDS(path_modelo_com)

cols_pred <- c(
  "cluster_id", "dia_objetivo", "version_cluster", "pred_prob",
  "tuvo_reclamo_observado", "n_reclamos_observado",
  "n_reclamos_lag1", "n_reclamos_sum_7d", "n_reclamos_sum_30d",
  "mean_tiempo_desde_ultimo_levante_pred", "n_contenedores_activos",
  "pct_contenedores_inferidos"
)

pred <- as.data.table(as.data.frame(
  open_dataset(path_pred) |>
    dplyr::select(dplyr::all_of(cols_pred)) |>
    dplyr::collect()
))
pred[, dia_objetivo := as.IDate(dia_objetivo)]
pred <- pred[!is.na(tuvo_reclamo_observado)]

version_cluster_obj <- unique(pred$version_cluster)
if (length(version_cluster_obj) != 1L) stop("Se esperaba una version_cluster")

ratio <- as.data.table(as.data.frame(
  open_dataset(path_features) |>
    dplyr::filter(version_cluster == !!version_cluster_obj) |>
    dplyr::select(
      cluster_id,
      dia,
      version_cluster,
      mean_ratio_tiempo_periodo_pred
    ) |>
    dplyr::collect()
))
setnames(ratio, "dia", "dia_objetivo")
ratio[, dia_objetivo := as.IDate(dia_objetivo)]
if (anyDuplicated(ratio, by = c("cluster_id", "dia_objetivo", "version_cluster"))) {
  stop("Ratio duplicado por cluster/dia/version")
}

pred <- ratio[pred, on = c("cluster_id", "dia_objetivo", "version_cluster")]

admin <- as.data.table(as.data.frame(open_dataset(path_admin)))[
  version_cluster == version_cluster_obj
]
segmento <- as.data.table(as.data.frame(open_dataset(path_segmento)))[
  version_cluster == version_cluster_obj
]

if (anyDuplicated(admin$cluster_id) || anyDuplicated(segmento$cluster_id)) {
  stop("Hay cluster_id duplicados en tablas territoriales")
}

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
      porc_vivienda_inadecuada_segmento
    )
  ],
  on = "cluster_id"
]

pred <- geo[pred, on = "cluster_id"]
pred[is.na(barrio) | !nzchar(barrio), barrio := "SIN_BARRIO"]
pred[is.na(ccz) | !nzchar(ccz), ccz := "SIN_CCZ"]

q_seguro <- function(x, p) {
  if (all(is.na(x))) return(NA_real_)
  as.numeric(quantile(x, p, na.rm = TRUE, type = 8))
}

construir_base <- function(dt, nivel = c("barrio", "ccz")) {
  nivel <- match.arg(nivel)
  densidad_col <- if (nivel == "barrio") "densidad_pob_barrio" else "densidad_pob_ccz"

  base <- dt[
    ,
    {
      ratio_valido <- mean_ratio_tiempo_periodo_pred[is.finite(mean_ratio_tiempo_periodo_pred)]
      exceso <- pmax(ratio_valido - 1, 0)
      n_ratio_valido <- length(ratio_valido)

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
        densidad_pob = mean(get(densidad_col), na.rm = TRUE),
        n_ratio_valido = n_ratio_valido,
        n_ratio_hasta_1 = sum(ratio_valido <= 1),
        n_ratio_1_1_5 = sum(ratio_valido > 1 & ratio_valido <= 1.5),
        n_ratio_1_5_2 = sum(ratio_valido > 1.5 & ratio_valido <= 2),
        n_ratio_mayor_2 = sum(ratio_valido > 2),
        pct_ratio_hasta_1 = if (n_ratio_valido > 0) mean(ratio_valido <= 1) else NA_real_,
        pct_ratio_1_1_5 = if (n_ratio_valido > 0) mean(ratio_valido > 1 & ratio_valido <= 1.5) else NA_real_,
        pct_ratio_1_5_2 = if (n_ratio_valido > 0) mean(ratio_valido > 1.5 & ratio_valido <= 2) else NA_real_,
        pct_ratio_mayor_2 = if (n_ratio_valido > 0) mean(ratio_valido > 2) else NA_real_,
        carga_exceso_total = sum(exceso),
        carga_exceso_media = if (n_ratio_valido > 0) mean(exceso) else NA_real_,
        ratio_medio_territorio = if (n_ratio_valido > 0) mean(ratio_valido) else NA_real_,
        ratio_p90_territorio = if (n_ratio_valido > 0) q_seguro(ratio_valido, 0.90) else NA_real_
      )
    },
    by = c("dia_objetivo", nivel)
  ]

  setnames(base, nivel, "territorio")
  base[, territorio := factor(territorio)]
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
  "pct_ratio_1_1_5", "pct_ratio_1_5_2", "pct_ratio_mayor_2",
  "carga_exceso_total", "carga_exceso_media", "ratio_medio_territorio", "ratio_p90_territorio",
  "nbi_medio", "asentamiento_medio", "vivienda_inadecuada_media", "densidad_pob"
)

preparar_features <- function(base) {
  train <- base[split_modelo == "entrenamiento"]
  prep <- rbindlist(lapply(features_continuas, function(v) {
    x <- as.numeric(train[[v]])
    x[!is.finite(x)] <- NA_real_
    mediana <- median(x, na.rm = TRUE)
    x[is.na(x)] <- mediana
    desvio <- sd(x)
    if (!is.finite(desvio) || desvio == 0) desvio <- 1
    data.table(variable = v, mediana = mediana, media = mean(x), desvio = desvio)
  }))

  for (i in seq_len(nrow(prep))) {
    v <- prep$variable[[i]]
    x <- as.numeric(base[[v]])
    x[!is.finite(x)] <- NA_real_
    x[is.na(x)] <- prep$mediana[[i]]
    base[, (paste0("z_", v)) := (x - prep$media[[i]]) / prep$desvio[[i]]]
  }
  list(base = base, prep = prep)
}

formulas <- list(
  M1 = prop_clusters_reclamo ~ dia_semana + mes +
    z_score_medio + z_score_sd + z_score_p90 +
    s(territorio, bs = "re"),
  M2 = prop_clusters_reclamo ~ dia_semana + mes +
    z_score_medio + z_score_sd + z_score_p90 +
    z_tiempo_levante_medio + z_tiempo_levante_p90 + z_pct_clusters_tiempo_3omas +
    z_contenedores_activos_medio + z_pct_inferidos_medio +
    z_reclamos_lag1_medio + z_reclamos_7d_medio + z_reclamos_30d_medio +
    s(territorio, bs = "re"),
  M3 = prop_clusters_reclamo ~ dia_semana + mes +
    z_score_medio + z_score_sd + z_score_p90 +
    z_tiempo_levante_medio + z_tiempo_levante_p90 + z_pct_clusters_tiempo_3omas +
    z_contenedores_activos_medio + z_pct_inferidos_medio +
    z_reclamos_lag1_medio + z_reclamos_7d_medio + z_reclamos_30d_medio +
    z_pct_ratio_1_1_5 + z_pct_ratio_1_5_2 + z_pct_ratio_mayor_2 +
    z_carga_exceso_total + z_carga_exceso_media +
    z_ratio_medio_territorio + z_ratio_p90_territorio +
    s(territorio, bs = "re"),
  M4 = prop_clusters_reclamo ~ dia_semana + mes +
    z_score_medio + z_score_sd + z_score_p90 +
    z_tiempo_levante_medio + z_tiempo_levante_p90 + z_pct_clusters_tiempo_3omas +
    z_contenedores_activos_medio + z_pct_inferidos_medio +
    z_reclamos_lag1_medio + z_reclamos_7d_medio + z_reclamos_30d_medio +
    z_pct_ratio_1_1_5 + z_pct_ratio_1_5_2 + z_pct_ratio_mayor_2 +
    z_carga_exceso_total + z_carga_exceso_media +
    z_ratio_medio_territorio + z_ratio_p90_territorio +
    z_nbi_medio + z_asentamiento_medio + z_vivienda_inadecuada_media + z_densidad_pob +
    z_tiempo_levante_medio:z_nbi_medio +
    z_carga_exceso_media:z_nbi_medio +
    z_score_medio:z_nbi_medio +
    s(territorio, bs = "re")
)

ajustar_escenarios <- function(base, nivel) {
  prep_obj <- preparar_features(copy(base))
  base <- prep_obj$base
  train <- base[split_modelo == "entrenamiento"]
  newdata <- as.data.frame(base[, setdiff(names(base), "dia_objetivo"), with = FALSE])

  fits <- list()
  predicciones <- list()
  diagnosticos <- list()

  for (escenario in names(formulas)) {
    fit <- bam(
      formulas[[escenario]],
      data = train,
      family = binomial(),
      weights = n_clusters,
      method = "fREML",
      discrete = TRUE,
      nthreads = 2L
    )
    prob <- as.numeric(mgcv::predict.gam(fit, newdata = newdata, type = "response"))

    pred <- base[
      ,
      .(
        dia_objetivo,
        split_modelo,
        territorio,
        n_clusters,
        clusters_con_reclamo,
        suma_scores
      )
    ]
    pred[, `:=`(
      escenario = escenario,
      nivel_territorial = nivel,
      prob_predicha = prob,
      clusters_esperados = n_clusters * prob
    )]

    fits[[escenario]] <- fit
    predicciones[[escenario]] <- pred
    diagnosticos[[escenario]] <- data.table(
      nivel_territorial = nivel,
      escenario = escenario,
      convergencia = if (isTRUE(fit$converged)) "OK" else "REVISAR",
      AIC = AIC(fit),
      logLik = as.numeric(logLik(fit)),
      n_coeficientes = length(coef(fit))
    )
  }

  list(
    base = base,
    prep = prep_obj$prep,
    fits = fits,
    predicciones = rbindlist(predicciones),
    diagnosticos = rbindlist(diagnosticos)
  )
}

agregar_ciudad <- function(pred) {
  pred[
    ,
    .(
      clusters_observados = sum(clusters_con_reclamo),
      clusters_esperados = sum(clusters_esperados),
      suma_scores = sum(suma_scores),
      n_clusters = sum(n_clusters)
    ),
    by = .(dia_objetivo, split_modelo, nivel_territorial, escenario)
  ]
}

calcular_metricas <- function(pred_ciudad, media_train) {
  periodos <- c("validacion", "test", "validacion + test")
  salida <- list()

  for (periodo in periodos) {
    dt_periodo <- if (periodo == "validacion + test") {
      pred_ciudad[split_modelo %in% c("validacion", "test")]
    } else {
      pred_ciudad[split_modelo == periodo]
    }

    for (escenario_actual in unique(dt_periodo$escenario)) {
      dt <- dt_periodo[escenario == escenario_actual]
      y <- dt$clusters_observados
      p <- dt$clusters_esperados
      salida[[length(salida) + 1L]] <- data.table(
        nivel_territorial = unique(dt$nivel_territorial),
        escenario = escenario_actual,
        periodo = periodo,
        dias = nrow(dt),
        media_observada = mean(y),
        media_predicha = mean(p),
        sesgo = mean(p - y),
        mae = mean(abs(p - y)),
        rmse = sqrt(mean((p - y)^2)),
        correlacion = cor(p, y),
        sd_observado = sd(y),
        sd_predicho = sd(p),
        razon_sd = sd(p) / sd(y)
      )
    }

    dt_m0 <- unique(dt_periodo[, .(
      dia_objetivo,
      split_modelo,
      nivel_territorial,
      clusters_observados,
      suma_scores
    )])
    y <- dt_m0$clusters_observados
    p <- dt_m0$suma_scores
    salida[[length(salida) + 1L]] <- data.table(
      nivel_territorial = unique(dt_m0$nivel_territorial),
      escenario = "M0_suma_scores",
      periodo = periodo,
      dias = nrow(dt_m0),
      media_observada = mean(y),
      media_predicha = mean(p),
      sesgo = mean(p - y),
      mae = mean(abs(p - y)),
      rmse = sqrt(mean((p - y)^2)),
      correlacion = cor(p, y),
      sd_observado = sd(y),
      sd_predicho = sd(p),
      razon_sd = sd(p) / sd(y)
    )
  }
  rbindlist(salida, fill = TRUE)
}

base_barrio <- construir_base(pred, "barrio")
base_ccz <- construir_base(pred, "ccz")

res_barrio <- ajustar_escenarios(base_barrio, "barrio")
res_ccz <- ajustar_escenarios(base_ccz, "ccz")

pred_ciudad <- rbindlist(list(
  agregar_ciudad(res_barrio$predicciones),
  agregar_ciudad(res_ccz$predicciones)
))

media_train <- pred[
  (year(dia_objetivo) * 100L + month(dia_objetivo)) %in% modelo_com$meses_train,
  .(clusters = sum(tuvo_reclamo_observado == 1L)),
  by = dia_objetivo
][, mean(clusters)]

metricas <- rbindlist(list(
  calcular_metricas(pred_ciudad[nivel_territorial == "barrio"], media_train),
  calcular_metricas(pred_ciudad[nivel_territorial == "ccz"], media_train)
))

diagnosticos <- rbindlist(list(res_barrio$diagnosticos, res_ccz$diagnosticos))
base_salida <- rbindlist(list(res_barrio$base, res_ccz$base), fill = TRUE)
prep_salida <- rbindlist(list(
  res_barrio$prep[, nivel_territorial := "barrio"],
  res_ccz$prep[, nivel_territorial := "ccz"]
), fill = TRUE)

fwrite(metricas, file.path(out_base, "metricas_m0_m4.csv"))
fwrite(diagnosticos, file.path(out_base, "diagnostico_m1_m4.csv"))
fwrite(pred_ciudad, file.path(out_base, "predicciones_diarias_m1_m4.csv"))
fwrite(base_salida, file.path(out_base, "base_territorio_dia_con_ratio.csv"))
fwrite(prep_salida, file.path(out_base, "preparacion_features.csv"))

for (escenario in names(formulas)) {
  saveRDS(
    res_barrio$fits[[escenario]],
    file.path(out_base, paste0("modelo_barrio_", escenario, ".rds"))
  )
  saveRDS(
    res_ccz$fits[[escenario]],
    file.path(out_base, paste0("modelo_ccz_", escenario, ".rds"))
  )
}

print(diagnosticos)
print(metricas[periodo == "test"])
