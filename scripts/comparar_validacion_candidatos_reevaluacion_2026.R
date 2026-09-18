library(arrow)
library(data.table)

source("funciones/modelos_utils.R")

path_com <- paste0(
  "data/processed/modelos/reevaluacion_2026/com_cluster/",
  "predicciones_validacion.parquet"
)
path_agregados <- paste0(
  "data/processed/modelos/reevaluacion_2026/agregados_inferencia/",
  "predicciones_diarias_validacion.csv"
)
path_zl <- paste0(
  "data/processed/modelos/reevaluacion_2026/zona_limpia/",
  "predicciones_validacion.parquet"
)
path_out <- "outputs/reevaluacion_2026/validacion"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

validar_periodo <- function(dt) {
  dt[, dia := as.IDate(dia)]
  if (dt[split != "validacion" | dia < as.IDate("2026-04-01") |
         dia > as.IDate("2026-06-30"), .N]) {
    stop("Hay filas fuera de la validacion congelada")
  }
  invisible(TRUE)
}

metricas_binarias <- function(dt, target_col = "target", score_col = "pred_prob") {
  dt[, {
    y <- as.integer(get(target_col))
    p <- as.numeric(get(score_col))
    .(
      filas = .N,
      positivos = sum(y),
      prevalencia = mean(y),
      auc = auc_binaria(y, p),
      logloss = logloss_binaria(y, p),
      brier = mean((p - y)^2),
      prob_media = mean(p)
    )
  }, by = candidato]
}

metricas_binarias_mes <- function(dt) {
  dt[, anio_mes := as.integer(format(dia, "%Y%m"))]
  dt[, {
    y <- as.integer(target)
    p <- as.numeric(pred_prob)
    .(
      filas = .N,
      positivos = sum(y),
      prevalencia = mean(y),
      auc = auc_binaria(y, p),
      logloss = logloss_binaria(y, p),
      brier = mean((p - y)^2)
    )
  }, by = .(candidato, anio_mes)]
}

lift_binario <- function(dt, cortes = c(0.01, 0.05, 0.10, 0.20)) {
  rbindlist(lapply(unique(dt$candidato), function(nombre) {
    ans <- lift_top(
      copy(dt[candidato == nombre]),
      score_col = "pred_prob", y_col = "target", cortes = cortes
    )
    ans[, candidato := nombre]
    ans
  }))
}

lift_diario_resumen <- function(dt, cortes = c(0.05, 0.10, 0.20)) {
  diario <- dt[, {
    d <- copy(.SD)
    setorder(d, -pred_prob)
    positivos_dia <- sum(d$target)
    prevalencia_dia <- mean(d$target)
    rbindlist(lapply(cortes, function(corte) {
      n_top <- max(1L, floor(.N * corte))
      top <- d[seq_len(n_top)]
      positivos_top <- sum(top$target)
      precision <- mean(top$target)
      data.table(
        top_pct = corte,
        precision = precision,
        capture_rate = fifelse(positivos_dia > 0, positivos_top / positivos_dia, NA_real_),
        lift = fifelse(prevalencia_dia > 0, precision / prevalencia_dia, NA_real_)
      )
    }))
  }, by = .(candidato, dia)]
  diario[, .(
    dias = .N,
    precision_media = mean(precision, na.rm = TRUE),
    capture_rate_medio = mean(capture_rate, na.rm = TRUE),
    lift_medio = mean(lift, na.rm = TRUE)
  ), by = .(candidato, top_pct)]
}

calibracion_deciles_candidato <- function(dt) {
  rbindlist(lapply(unique(dt$candidato), function(nombre) {
    ans <- calibracion_deciles(
      copy(dt[candidato == nombre]),
      score_col = "pred_prob", y_col = "target"
    )
    ans[, candidato := nombre]
    ans
  }))
}

metricas_conteo <- function(dt, grupos) {
  dt[, {
    error <- predicho - observado
    sst <- sum((observado - mean(observado))^2)
    .(
      dias = .N,
      media_observada = mean(observado),
      media_predicha = mean(predicho),
      sesgo = mean(error),
      mae = mean(abs(error)),
      rmse = sqrt(mean(error^2)),
      correlacion = cor(observado, predicho),
      r2 = fifelse(sst > 0, 1 - sum(error^2) / sst, NA_real_),
      razon_sd = sd(predicho) / sd(observado)
    )
  }, by = grupos]
}

com <- as.data.table(arrow::read_parquet(path_com))
validar_periodo(com)
metricas_com <- metricas_binarias(com)
metricas_com_mes <- metricas_binarias_mes(com)
lift_com <- lift_binario(com)
lift_diario_com <- lift_diario_resumen(com)
calibracion_com <- calibracion_deciles_candidato(com)

agregados <- fread(path_agregados)
validar_periodo(agregados)
metricas_agregados <- metricas_conteo(agregados, "candidato")
agregados[, anio_mes := as.integer(format(dia, "%Y%m"))]
metricas_agregados_mes <- metricas_conteo(
  agregados, c("candidato", "anio_mes")
)

zl <- as.data.table(arrow::read_parquet(path_zl))
validar_periodo(zl)
metricas_zl <- metricas_binarias(zl)
metricas_zl_mes <- metricas_binarias_mes(zl)
lift_zl <- lift_binario(zl, cortes = c(0.05, 0.10, 0.20, 0.30))
lift_diario_zl <- lift_diario_resumen(zl, cortes = c(0.10, 0.20, 0.30))
calibracion_zl <- calibracion_deciles_candidato(zl)

ref_com <- metricas_com[candidato == "com_logistico_reducido_d2"]
comparacion_com <- copy(metricas_com)
comparacion_com[, `:=`(
  delta_auc_vs_logistico = auc - ref_com$auc,
  delta_logloss_vs_logistico = logloss - ref_com$logloss,
  delta_brier_vs_logistico = brier - ref_com$brier
)]

ref_a0 <- metricas_agregados[candidato == "pronostico_a0"]
comparacion_agregados <- copy(metricas_agregados)
comparacion_agregados[, `:=`(
  delta_rmse_vs_a0 = rmse - ref_a0$rmse,
  delta_mae_vs_a0 = mae - ref_a0$mae,
  delta_correlacion_vs_a0 = correlacion - ref_a0$correlacion
)]

ref_zl <- metricas_zl[candidato == "zl_operativo_segmento"]
comparacion_zl <- copy(metricas_zl)
comparacion_zl[, `:=`(
  delta_auc_vs_operativo_segmento = auc - ref_zl$auc,
  delta_logloss_vs_operativo_segmento = logloss - ref_zl$logloss,
  delta_brier_vs_operativo_segmento = brier - ref_zl$brier
)]

salidas <- list(
  metricas_com = metricas_com,
  metricas_com_mes = metricas_com_mes,
  lift_com = lift_com,
  lift_diario_com = lift_diario_com,
  calibracion_com = calibracion_com,
  comparacion_com = comparacion_com,
  metricas_agregados = metricas_agregados,
  metricas_agregados_mes = metricas_agregados_mes,
  comparacion_agregados = comparacion_agregados,
  metricas_zl = metricas_zl,
  metricas_zl_mes = metricas_zl_mes,
  lift_zl = lift_zl,
  lift_diario_zl = lift_diario_zl,
  calibracion_zl = calibracion_zl,
  comparacion_zl = comparacion_zl
)
for (nombre in names(salidas)) {
  fwrite(salidas[[nombre]], file.path(path_out, paste0(nombre, ".csv")))
}

cat("\nCOM cluster/dia:\n")
print(comparacion_com[order(-auc)])
cat("\nPronostico agregado e inferencia:\n")
print(comparacion_agregados[order(rmse)])
cat("\nZona Limpia:\n")
print(comparacion_zl[order(-auc)])
