library(arrow)
library(data.table)
library(mgcv)

set.seed(20260914)

path_base <- file.path(
  "outputs", "comparacion_ventanas_propension_xgboost_com",
  "base_segmento_dia_ventanas.csv"
)
path_territorio <- file.path(
  "data", "processed", "cluster_territorial", "cluster_segmento_censal"
)
path_feriados <- file.path("data", "reference", "feriados", "feriados.R")
path_modelos <- file.path("outputs", "modelo_inferencial_segmento_com")
path_out <- file.path(path_modelos, "diagnostico_temporal")
path_boot <- file.path(path_out, "bootstrap_semanal_replicas")
dir.create(path_boot, recursive = TRUE, showWarnings = FALSE)

n_boot <- as.integer(Sys.getenv("BOOT_REPS", "50"))
if (!is.finite(n_boot) || n_boot < 1L) stop("BOOT_REPS debe ser positivo")
boot_desde <- as.integer(Sys.getenv("BOOT_DESDE", "1"))
boot_hasta <- as.integer(Sys.getenv("BOOT_HASTA", as.character(n_boot)))
ejecutar_rolling <- Sys.getenv("EJECUTAR_ROLLING", "1") == "1"
solo_resumir_boot <- Sys.getenv("SOLO_RESUMIR_BOOT", "0") == "1"

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
    dplyr::select(codseg_centroide, porc_nbi_segmento, densidad_pob_km2) |>
    dplyr::collect()
))
territorio_cluster[, segmento := as.character(codseg_centroide)]
territorio_segmento <- territorio_cluster[, .(
  porc_nbi_segmento = first(porc_nbi_segmento),
  densidad_pob_km2 = first(densidad_pob_km2),
  n_nbi = uniqueN(porc_nbi_segmento),
  n_densidad = uniqueN(densidad_pob_km2)
), by = segmento]
if (territorio_segmento[n_nbi > 1L | n_densidad > 1L, .N] > 0L) {
  stop("Un segmento tiene mas de un valor territorial")
}
territorio_segmento[, c("n_nbi", "n_densidad") := NULL]
base[territorio_segmento, on = "segmento", `:=`(
  porc_nbi_segmento = i.porc_nbi_segmento,
  densidad_pob_km2 = i.densidad_pob_km2
)]
if (base[!is.finite(porc_nbi_segmento) | !is.finite(densidad_pob_km2), .N]) {
  stop("Hay filas sin variables territoriales")
}

base[, `:=`(
  log_densidad_pob = log1p(densidad_pob_km2),
  es_feriado = factor(as.integer(dia_objetivo %in% feriados)),
  prop_reclamo = observado / n_clusters,
  dia_semana = factor(dia_semana),
  barrio = factor(barrio),
  segmento = factor(segmento)
)]

variables_continuas <- c(
  "log_densidad_pob", "porc_nbi_segmento", "media_h",
  "media_q_60", "delta_q_7_60"
)

estandarizar <- function(datos, referencia) {
  datos <- copy(datos)
  prep <- rbindlist(lapply(variables_continuas, function(variable) {
    x <- as.numeric(referencia[[variable]])
    x[!is.finite(x)] <- NA_real_
    mediana <- median(x, na.rm = TRUE)
    x[is.na(x)] <- mediana
    desvio <- sd(x)
    if (!is.finite(desvio) || desvio == 0) desvio <- 1
    data.table(
      variable = variable,
      mediana = mediana,
      media = mean(x),
      desvio = desvio
    )
  }))
  for (i in seq_len(nrow(prep))) {
    variable <- prep$variable[[i]]
    x <- as.numeric(datos[[variable]])
    x[!is.finite(x)] <- NA_real_
    x[is.na(x)] <- prep$mediana[[i]]
    datos[, paste0("z_", variable) :=
      (x - prep$media[[i]]) / prep$desvio[[i]]]
  }
  list(datos = datos, preparacion = prep)
}

formulas <- list(
  I2_historia = prop_reclamo ~
    dia_semana + es_feriado +
    z_log_densidad_pob + z_porc_nbi_segmento +
    z_media_h + z_media_q_60 + z_delta_q_7_60 +
    s(barrio, bs = "re") + s(segmento, bs = "re"),
  I4_calendario = prop_reclamo ~
    dia_semana + es_feriado +
    z_log_densidad_pob + z_porc_nbi_segmento +
    z_media_h + z_media_q_60 + z_delta_q_7_60 +
    z_media_h:z_media_q_60 +
    z_media_h:dia_semana + z_media_h:es_feriado +
    s(barrio, bs = "re") + s(segmento, bs = "re")
)

ajustar <- function(formula, datos) {
  bam(
    formula, data = datos, family = binomial(), weights = n_clusters,
    method = "fREML", discrete = TRUE, nthreads = 2L
  )
}

predecir_nuevos <- function(fit, datos, train) {
  segmentos_train <- levels(droplevels(train$segmento))
  barrios_train <- levels(droplevels(train$barrio))
  es_nuevo <- !as.character(datos$segmento) %in% segmentos_train
  pred <- rep(NA_real_, nrow(datos))
  if (any(!es_nuevo)) {
    nd <- as.data.frame(datos[!es_nuevo])
    nd$segmento <- factor(nd$segmento, levels = segmentos_train)
    nd$barrio <- factor(nd$barrio, levels = barrios_train)
    pred[!es_nuevo] <- predict(fit, newdata = nd, type = "response")
  }
  if (any(es_nuevo)) {
    nd <- as.data.frame(datos[es_nuevo])
    nd$segmento <- factor(segmentos_train[[1L]], levels = segmentos_train)
    nd$barrio <- factor(nd$barrio, levels = barrios_train)
    pred[es_nuevo] <- predict(
      fit, newdata = nd, type = "response", exclude = "s(segmento)"
    )
  }
  as.numeric(pred)
}

metricas <- function(observado, predicho) {
  error <- predicho - observado
  data.table(
    n_dias = length(observado),
    sesgo = mean(error),
    mae = mean(abs(error)),
    rmse = sqrt(mean(error^2)),
    correlacion = if (length(observado) > 2L) cor(observado, predicho) else NA_real_
  )
}

# 1. Diagnostico de los modelos originales por fecha, mes y condiciones del dia.
pred_original <- fread(file.path(path_modelos, "predicciones_diarias.csv"))
pred_original[, dia_objetivo := as.IDate(dia_objetivo)]
pred_original <- pred_original[
  escenario %in% c("I2_historia", "I4_calendario", "XGBoost_referencia") &
    split_modelo %in% c("validacion", "test")
]

pred_ancha <- dcast(
  pred_original,
  split_modelo + dia_objetivo + observado ~ escenario,
  value.var = "predicho"
)
pred_ancha[, `:=`(
  mes = format(dia_objetivo, "%Y-%m"),
  dia_semana = weekdays(as.Date(dia_objetivo)),
  es_feriado = as.integer(dia_objetivo %in% feriados),
  error_abs_I2 = abs(I2_historia - observado),
  error_abs_I4 = abs(I4_calendario - observado),
  error_abs_XGB = abs(XGBoost_referencia - observado),
  delta_abs_I2_XGB = abs(I2_historia - observado) -
    abs(XGBoost_referencia - observado),
  delta_abs_I4_XGB = abs(I4_calendario - observado) -
    abs(XGBoost_referencia - observado)
)]

agregado_dia <- base[, .(
  n_clusters = sum(n_clusters),
  media_h = weighted.mean(media_h, n_clusters),
  media_q_60 = weighted.mean(media_q_60, n_clusters),
  delta_q_7_60 = weighted.mean(delta_q_7_60, n_clusters)
), by = dia_objetivo]
pred_ancha[agregado_dia, on = "dia_objetivo", `:=`(
  n_clusters = i.n_clusters,
  media_h = i.media_h,
  media_q_60 = i.media_q_60,
  delta_q_7_60 = i.delta_q_7_60
)]

pred_larga <- melt(
  pred_original,
  id.vars = c("escenario", "split_modelo", "dia_objetivo", "observado"),
  measure.vars = "predicho"
)
diagnostico_mes <- pred_larga[, metricas(observado, value),
  by = .(escenario, split_modelo, mes = format(dia_objetivo, "%Y-%m"))]

diagnostico_grupo <- rbindlist(list(
  pred_ancha[, .(
    n_dias = .N,
    delta_abs_I2_XGB = mean(delta_abs_I2_XGB),
    delta_abs_I4_XGB = mean(delta_abs_I4_XGB)
  ), by = .(grupo = dia_semana)][, variable := "dia_semana"],
  pred_ancha[, .(
    n_dias = .N,
    delta_abs_I2_XGB = mean(delta_abs_I2_XGB),
    delta_abs_I4_XGB = mean(delta_abs_I4_XGB)
  ), by = .(grupo = as.character(es_feriado))][, variable := "es_feriado"]
), use.names = TRUE)

for (variable in c("observado", "media_h", "media_q_60", "delta_q_7_60")) {
  cortes <- unique(quantile(pred_ancha[[variable]], probs = seq(0, 1, .25), na.rm = TRUE))
  grupo <- cut(pred_ancha[[variable]], breaks = cortes, include.lowest = TRUE)
  tmp <- copy(pred_ancha)[, grupo_tmp := grupo][, .(
    n_dias = .N,
    delta_abs_I2_XGB = mean(delta_abs_I2_XGB),
    delta_abs_I4_XGB = mean(delta_abs_I4_XGB)
  ), by = .(grupo = as.character(grupo_tmp))]
  tmp[, variable := variable]
  diagnostico_grupo <- rbindlist(list(diagnostico_grupo, tmp), use.names = TRUE)
}

fwrite(pred_ancha, file.path(path_out, "comparacion_error_diario.csv"))
fwrite(diagnostico_mes, file.path(path_out, "metricas_modelos_originales_por_mes.csv"))
fwrite(diagnostico_grupo, file.path(path_out, "ventaja_xgboost_por_condicion.csv"))

# 2 y 3. Origen expansivo mensual y estabilidad de coeficientes.
meses_evaluacion <- as.IDate(c(
  "2026-01-01", "2026-02-01", "2026-03-01", "2026-04-01", "2026-05-01"
))
metricas_rolling <- list()
coef_rolling <- list()

if (ejecutar_rolling && !solo_resumir_boot) for (indice_mes in seq_along(meses_evaluacion)) {
  inicio_mes <- meses_evaluacion[[indice_mes]]
  fin_mes <- as.IDate(seq(as.Date(inicio_mes), by = "1 month", length.out = 2L)[2L] - 1)
  fin_mes <- min(fin_mes, max(base$dia_objetivo))
  est <- estandarizar(base, base[dia_objetivo < inicio_mes])
  datos_est <- est$datos
  train_roll <- droplevels(datos_est[dia_objetivo < inicio_mes])
  eval_roll <- datos_est[dia_objetivo >= inicio_mes & dia_objetivo <= fin_mes]
  if (!nrow(eval_roll)) next

  for (escenario in names(formulas)) {
    cat("Rolling", as.character(inicio_mes), escenario, "\n")
    fit <- ajustar(formulas[[escenario]], train_roll)
    prob <- predecir_nuevos(fit, eval_roll, train_roll)
    eval_roll[, prob_predicha_tmp := prob]
    pred_dia <- eval_roll[, .(
      observado = sum(observado),
      predicho = sum(n_clusters * prob_predicha_tmp)
    ), by = dia_objetivo]
    met <- metricas(pred_dia$observado, pred_dia$predicho)
    met[, `:=`(
      escenario = escenario,
      inicio_train = min(train_roll$dia_objetivo),
      fin_train = max(train_roll$dia_objetivo),
      inicio_evaluacion = as.IDate(inicio_mes),
      fin_evaluacion = fin_mes
    )]
    metricas_rolling[[length(metricas_rolling) + 1L]] <- met

    tabla <- as.data.table(summary(fit)$p.table, keep.rownames = "termino")
    setnames(tabla, 2:5, c("estimacion", "error_std", "estadistico", "p_valor"))
    tabla <- tabla[grepl("z_", termino)]
    tabla[, `:=`(
      escenario = escenario,
      fin_train = max(train_roll$dia_objetivo),
      inicio_evaluacion = as.IDate(inicio_mes)
    )]
    coef_rolling[[length(coef_rolling) + 1L]] <- tabla
  }
}
if (length(metricas_rolling)) {
  fwrite(rbindlist(metricas_rolling), file.path(path_out, "metricas_origen_expansivo.csv"))
  fwrite(rbindlist(coef_rolling), file.path(path_out, "coeficientes_origen_expansivo.csv"))
}

# 4. Bootstrap piloto: las semanas se remuestrean como bloques completos.
est_original <- estandarizar(base, base[split_modelo == "entrenamiento"])
train_original <- droplevels(est_original$datos[split_modelo == "entrenamiento"])
train_original[, semana_inicio := dia_objetivo - (as.integer(format(dia_objetivo, "%u")) - 1L)]
semanas <- sort(unique(train_original$semana_inicio))

if (!solo_resumir_boot) for (b in seq.int(boot_desde, boot_hasta)) {
  path_rep <- file.path(path_boot, sprintf("replica_%03d.csv", b))
  if (file.exists(path_rep)) next
  set.seed(20260914 + b)
  semanas_b <- sample(semanas, length(semanas), replace = TRUE)
  boot <- rbindlist(lapply(seq_along(semanas_b), function(i) {
    train_original[semana_inicio == semanas_b[[i]]]
  }))

  resultados_b <- list()
  for (escenario in names(formulas)) {
    cat("Bootstrap", b, "de", n_boot, escenario, "\n")
    resultado <- tryCatch({
      fit <- ajustar(formulas[[escenario]], boot)
      tabla <- as.data.table(summary(fit)$p.table, keep.rownames = "termino")
      setnames(tabla, 2:5, c("estimacion", "error_std_modelo", "estadistico", "p_valor_modelo"))
      tabla <- tabla[grepl("z_", termino), .(
        termino, estimacion, error_std_modelo, convergio = isTRUE(fit$converged)
      )]
      tabla[, `:=`(replica = b, escenario = escenario, error = NA_character_)]
      tabla
    }, error = function(e) {
      data.table(
        termino = NA_character_, estimacion = NA_real_, error_std_modelo = NA_real_,
        convergio = FALSE, replica = b, escenario = escenario,
        error = conditionMessage(e)
      )
    })
    resultados_b[[escenario]] <- resultado
  }
  fwrite(rbindlist(resultados_b, fill = TRUE), path_rep)
}

archivos_boot <- list.files(path_boot, pattern = "^replica_[0-9]+[.]csv$", full.names = TRUE)
boot_resultados <- rbindlist(lapply(archivos_boot, fread), fill = TRUE)
fwrite(boot_resultados, file.path(path_out, "bootstrap_semanal_coeficientes.csv"))

boot_resumen <- boot_resultados[convergio == TRUE & !is.na(termino), .(
  n_replicas = .N,
  media = mean(estimacion),
  error_std_bootstrap = sd(estimacion),
  q025 = quantile(estimacion, .025),
  mediana = median(estimacion),
  q975 = quantile(estimacion, .975),
  proporcion_positiva = mean(estimacion > 0)
), by = .(escenario, termino)]
fwrite(boot_resumen, file.path(path_out, "bootstrap_semanal_resumen.csv"))

coef_original <- fread(file.path(path_modelos, "coeficientes.csv"))[
  escenario %in% names(formulas) & grepl("z_", termino),
  .(escenario, termino, estimacion_original = estimacion,
    error_std_convencional = error_std)
]
comparacion_incertidumbre <- merge(
  coef_original, boot_resumen, by = c("escenario", "termino"), all.x = TRUE
)
comparacion_incertidumbre[, `:=`(
  razon_error_std = error_std_bootstrap / error_std_convencional,
  convencional_bajo = estimacion_original - 1.96 * error_std_convencional,
  convencional_alto = estimacion_original + 1.96 * error_std_convencional
)]
fwrite(
  comparacion_incertidumbre,
  file.path(path_out, "comparacion_incertidumbre_convencional_bootstrap.csv")
)

cat("\nMetricas originales por mes:\n")
print(diagnostico_mes[order(mes, rmse)])
if (file.exists(file.path(path_out, "metricas_origen_expansivo.csv"))) {
  cat("\nMetricas con origen expansivo:\n")
  print(fread(file.path(path_out, "metricas_origen_expansivo.csv"))[
    order(inicio_evaluacion, rmse)
  ])
}
cat("\nResumen bootstrap:\n")
print(boot_resumen)
cat("\nComparacion de errores estandar:\n")
print(comparacion_incertidumbre[, .(
  escenario, termino, estimacion_original, error_std_convencional,
  error_std_bootstrap, razon_error_std, q025, q975
)])
