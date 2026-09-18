library(arrow)
library(data.table)
library(mgcv)

path_base <- file.path(
  "outputs", "comparacion_ventanas_propension_xgboost_com",
  "base_segmento_dia_ventanas.csv"
)
path_territorio <- file.path(
  "data", "processed", "cluster_territorial", "cluster_segmento_censal"
)
path_feriados <- file.path("data", "reference", "feriados", "feriados.R")
path_pred_xgb <- file.path(
  "outputs", "comparacion_poda_xgboost_com", "predicciones_diarias.csv"
)
path_out <- file.path("outputs", "modelo_inferencial_segmento_com")
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

env_feriados <- new.env(parent = baseenv())
sys.source(path_feriados, envir = env_feriados)
feriados <- as.IDate(env_feriados$diasDesc)

base <- fread(path_base)
base[, `:=`(
  dia_objetivo = as.IDate(dia_objetivo),
  segmento = as.character(segmento),
  delta_q_7_60 = media_q_7 - media_q_60
)]

territorio_cluster <- as.data.table(as.data.frame(
  open_dataset(path_territorio) |>
    dplyr::select(
      codseg_centroide, porc_nbi_segmento, densidad_pob_km2
    ) |>
    dplyr::collect()
))
territorio_cluster[, segmento := as.character(codseg_centroide)]

territorio_segmento <- territorio_cluster[, .(
  n_nbi = uniqueN(porc_nbi_segmento),
  n_densidad = uniqueN(densidad_pob_km2),
  porc_nbi_segmento = first(porc_nbi_segmento),
  densidad_pob_km2 = first(densidad_pob_km2)
), by = segmento]
if (territorio_segmento[n_nbi > 1L | n_densidad > 1L, .N] > 0L) {
  stop("Un segmento tiene mas de un valor de NBI o densidad")
}
territorio_segmento[, c("n_nbi", "n_densidad") := NULL]

base[territorio_segmento, on = "segmento", `:=`(
  porc_nbi_segmento = i.porc_nbi_segmento,
  densidad_pob_km2 = i.densidad_pob_km2
)]
if (base[!is.finite(porc_nbi_segmento) | !is.finite(densidad_pob_km2), .N] > 0L) {
  stop("Hay filas sin NBI o densidad de segmento")
}

base[, `:=`(
  log_densidad_pob = log1p(densidad_pob_km2),
  es_feriado = factor(as.integer(dia_objetivo %in% feriados)),
  prop_reclamo = observado / n_clusters
)]

# Los niveles se fijan con toda la base; se valida aparte que todos esten en train.
base[, `:=`(
  dia_semana = factor(dia_semana),
  barrio = factor(barrio),
  segmento = factor(segmento)
)]

train <- droplevels(base[split_modelo == "entrenamiento"])
nuevos_barrio <- setdiff(levels(base$barrio), unique(as.character(train$barrio)))
nuevos_segmento <- setdiff(levels(base$segmento), unique(as.character(train$segmento)))
if (length(nuevos_barrio) > 0L) {
  stop("Hay barrios fuera de entrenamiento")
}

variables_continuas <- c(
  "log_densidad_pob", "porc_nbi_segmento", "media_h",
  "media_q_60", "delta_q_7_60"
)

preparacion <- rbindlist(lapply(variables_continuas, function(variable) {
  x <- as.numeric(train[[variable]])
  x[!is.finite(x)] <- NA_real_
  mediana <- median(x, na.rm = TRUE)
  x[is.na(x)] <- mediana
  desvio <- sd(x)
  if (!is.finite(desvio) || desvio == 0) desvio <- 1
  data.table(
    variable = variable,
    mediana_train = mediana,
    media_train = mean(x),
    sd_train = desvio
  )
}))

for (i in seq_len(nrow(preparacion))) {
  variable <- preparacion$variable[[i]]
  x <- as.numeric(base[[variable]])
  x[!is.finite(x)] <- NA_real_
  x[is.na(x)] <- preparacion$mediana_train[[i]]
  base[, paste0("z_", variable) :=
    (x - preparacion$media_train[[i]]) / preparacion$sd_train[[i]]]
}
train <- droplevels(base[split_modelo == "entrenamiento"])

predecir_con_segmentos_nuevos <- function(fit, datos, train) {
  segmentos_train <- levels(train$segmento)
  barrios_train <- levels(train$barrio)
  es_nuevo <- !as.character(datos$segmento) %in% segmentos_train
  pred <- rep(NA_real_, nrow(datos))

  if (any(!es_nuevo)) {
    nd <- as.data.frame(datos[!es_nuevo])
    nd$segmento <- factor(nd$segmento, levels = segmentos_train)
    nd$barrio <- factor(nd$barrio, levels = barrios_train)
    pred[!es_nuevo] <- as.numeric(predict.gam(
      fit, newdata = nd, type = "response"
    ))
  }

  if (any(es_nuevo)) {
    nd <- as.data.frame(datos[es_nuevo])
    nd$segmento <- factor(segmentos_train[[1L]], levels = segmentos_train)
    nd$barrio <- factor(nd$barrio, levels = barrios_train)
    pred[es_nuevo] <- as.numeric(predict.gam(
      fit,
      newdata = nd,
      type = "response",
      exclude = "s(segmento)"
    ))
  }
  pred
}

formulas <- list(
  I0_estructura = prop_reclamo ~
    dia_semana + es_feriado +
    z_log_densidad_pob + z_porc_nbi_segmento +
    s(barrio, bs = "re") + s(segmento, bs = "re"),

  I1_operacion = prop_reclamo ~
    dia_semana + es_feriado +
    z_log_densidad_pob + z_porc_nbi_segmento +
    z_media_h +
    s(barrio, bs = "re") + s(segmento, bs = "re"),

  I2_historia = prop_reclamo ~
    dia_semana + es_feriado +
    z_log_densidad_pob + z_porc_nbi_segmento +
    z_media_h + z_media_q_60 + z_delta_q_7_60 +
    s(barrio, bs = "re") + s(segmento, bs = "re"),

  I3_sensibilidad = prop_reclamo ~
    dia_semana + es_feriado +
    z_log_densidad_pob + z_porc_nbi_segmento +
    z_media_h + z_media_q_60 + z_delta_q_7_60 +
    z_media_h:z_media_q_60 +
    s(barrio, bs = "re") + s(segmento, bs = "re"),

  I4_calendario = prop_reclamo ~
    dia_semana + es_feriado +
    z_log_densidad_pob + z_porc_nbi_segmento +
    z_media_h + z_media_q_60 + z_delta_q_7_60 +
    z_media_h:z_media_q_60 +
    z_media_h:dia_semana + z_media_h:es_feriado +
    s(barrio, bs = "re") + s(segmento, bs = "re")
)

metricas_fun <- function(dt) {
  error <- dt$predicho - dt$observado
  sse <- sum(error^2)
  sst <- sum((dt$observado - mean(dt$observado))^2)
  data.table(
    dias = nrow(dt),
    media_observada = mean(dt$observado),
    media_predicha = mean(dt$predicho),
    sesgo = mean(error),
    mae = mean(abs(error)),
    rmse = sqrt(mean(error^2)),
    correlacion = cor(dt$observado, dt$predicho),
    r2 = 1 - sse / sst,
    razon_sd = sd(dt$predicho) / sd(dt$observado)
  )
}

ajustes <- list()
predicciones_segmento <- list()
predicciones_dia <- list()
diagnosticos <- list()
coeficientes <- list()

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
  ajustes[[escenario]] <- fit
  saveRDS(fit, file.path(path_out, paste0("modelo_", escenario, ".rds")))

  prob <- predecir_con_segmentos_nuevos(fit, base, train)
  pred_seg <- base[, .(
    dia_objetivo, split_modelo, barrio, segmento,
    n_clusters, observado
  )]
  pred_seg[, `:=`(
    escenario = escenario,
    prob_predicha = prob,
    predicho = n_clusters * prob
  )]
  predicciones_segmento[[escenario]] <- pred_seg

  pred_dia <- pred_seg[, .(
    observado = sum(observado),
    predicho = sum(predicho),
    n_clusters = sum(n_clusters)
  ), by = .(escenario, split_modelo, dia_objetivo)]
  predicciones_dia[[escenario]] <- pred_dia

  resumen_fit <- summary(fit)
  diagnosticos[[escenario]] <- data.table(
    escenario = escenario,
    convergencia = if (isTRUE(fit$converged)) "OK" else "REVISAR",
    AIC = AIC(fit),
    logLik = as.numeric(logLik(fit)),
    devianza_explicada = resumen_fit$dev.expl,
    n_coeficientes = length(coef(fit))
  )

  tabla_coef <- as.data.table(
    resumen_fit$p.table,
    keep.rownames = "termino"
  )
  setnames(
    tabla_coef,
    2:5,
    c("estimacion", "error_std", "estadistico", "p_valor")
  )
  tabla_coef[, `:=`(
    escenario = escenario,
    conf_bajo = estimacion - 1.96 * error_std,
    conf_alto = estimacion + 1.96 * error_std
  )]
  tabla_coef[, `:=`(
    odds_ratio = exp(estimacion),
    or_conf_bajo = exp(conf_bajo),
    or_conf_alto = exp(conf_alto)
  )]
  coeficientes[[escenario]] <- tabla_coef
}

pred_segmento <- rbindlist(predicciones_segmento)
pred_dia <- rbindlist(predicciones_dia)

pred_a0 <- base[, .(
  escenario = "A0_referencia",
  observado = sum(observado),
  predicho = sum(n_clusters * prob_a0),
  n_clusters = sum(n_clusters)
), by = .(split_modelo, dia_objetivo)]

pred_xgb <- fread(path_pred_xgb)[
  escenario == "P3_compacto",
  .(
    escenario = "XGBoost_referencia",
    split_modelo,
    dia_objetivo = as.IDate(dia_objetivo),
    observado,
    predicho
  )
]
pred_xgb[base[, .(n_clusters = sum(n_clusters)), by = dia_objetivo],
  on = "dia_objetivo", n_clusters := i.n_clusters]

pred_dia_comparacion <- rbindlist(
  list(pred_dia, pred_a0, pred_xgb),
  use.names = TRUE,
  fill = TRUE
)

metricas_periodo <- pred_dia_comparacion[
  split_modelo %in% c("validacion", "test"),
  metricas_fun(.SD),
  by = .(escenario, split_modelo)
]
metricas_combinadas <- pred_dia_comparacion[
  split_modelo %in% c("validacion", "test"),
  metricas_fun(.SD),
  by = escenario
][, split_modelo := "validacion + test"]
setcolorder(metricas_combinadas, names(metricas_periodo))
metricas <- rbindlist(list(metricas_periodo, metricas_combinadas))

fwrite(preparacion, file.path(path_out, "preparacion_variables.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnostico_modelos.csv"))
fwrite(rbindlist(coeficientes), file.path(path_out, "coeficientes.csv"))
fwrite(pred_dia_comparacion, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas, file.path(path_out, "metricas_diarias.csv"))

cat("Diagnostico de ajustes:\n")
print(rbindlist(diagnosticos))
cat("\nMetricas de validacion:\n")
print(metricas[split_modelo == "validacion"][order(rmse)])
cat("\nMetricas de test:\n")
print(metricas[split_modelo == "test"][order(rmse)])
cat("\nMetricas combinadas:\n")
print(metricas[split_modelo == "validacion + test"][order(rmse)])
cat("\nCoeficientes continuos e interacciones de I4:\n")
print(rbindlist(coeficientes)[
  escenario == "I4_calendario" &
    grepl("z_", termino)
][, .(
  termino, estimacion, error_std, p_valor,
  odds_ratio, or_conf_bajo, or_conf_alto
)])
