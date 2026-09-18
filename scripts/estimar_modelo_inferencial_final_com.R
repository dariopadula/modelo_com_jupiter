library(arrow)
library(data.table)
library(mgcv)

set.seed(20260914)

ajustar_final <- Sys.getenv("AJUSTAR_FINAL", "1") == "1"
ejecutar_boot <- Sys.getenv("EJECUTAR_BOOT", "1") == "1"
solo_resumir <- Sys.getenv("SOLO_RESUMIR", "0") == "1"
boot_desde <- as.integer(Sys.getenv("BOOT_DESDE", "1"))
boot_hasta <- as.integer(Sys.getenv("BOOT_HASTA", "50"))

path_base <- file.path(
  "outputs", "comparacion_ventanas_propension_xgboost_com",
  "base_segmento_dia_ventanas.csv"
)
path_territorio <- file.path(
  "data", "processed", "cluster_territorial", "cluster_segmento_censal"
)
path_feriados <- file.path("data", "reference", "feriados", "feriados.R")
path_modelos <- file.path("outputs", "modelo_inferencial_segmento_com")
path_out <- file.path(path_modelos, "modelo_final_delta")
path_replicas <- file.path(path_out, "bootstrap_replicas")
dir.create(path_replicas, recursive = TRUE, showWarnings = FALSE)

env_feriados <- new.env(parent = baseenv())
sys.source(path_feriados, envir = env_feriados)
feriados <- as.IDate(env_feriados$diasDesc)

base <- fread(path_base)
base[, `:=`(
  dia_objetivo = as.IDate(dia_objetivo),
  segmento = as.character(segmento),
  delta_q_7_60 = media_q_7 - media_q_60
)]

territorio <- as.data.table(as.data.frame(
  open_dataset(path_territorio) |>
    dplyr::select(codseg_centroide, porc_nbi_segmento, densidad_pob_km2) |>
    dplyr::collect()
))
territorio[, segmento := as.character(codseg_centroide)]
territorio <- territorio[, .(
  n_nbi = uniqueN(porc_nbi_segmento),
  n_densidad = uniqueN(densidad_pob_km2),
  porc_nbi_segmento = first(porc_nbi_segmento),
  densidad_pob_km2 = first(densidad_pob_km2)
), by = segmento]
if (territorio[n_nbi > 1L | n_densidad > 1L, .N]) {
  stop("Un segmento tiene mas de un valor territorial")
}
territorio[, c("n_nbi", "n_densidad") := NULL]
base[territorio, on = "segmento", `:=`(
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

preparacion <- fread(file.path(path_modelos, "preparacion_variables.csv"))
for (variable_actual in preparacion$variable) {
  p <- preparacion[match(variable_actual, preparacion[["variable"]])]
  x <- as.numeric(base[[variable_actual]])
  x[!is.finite(x)] <- NA_real_
  x[is.na(x)] <- p$mediana_train
  base[, paste0("z_", variable_actual) :=
    (x - p$media_train) / p$sd_train]
}

train <- droplevels(base[split_modelo == "entrenamiento"])
formula_final <- prop_reclamo ~
  dia_semana + es_feriado +
  z_log_densidad_pob + z_porc_nbi_segmento +
  z_media_h + z_media_q_60 + z_delta_q_7_60 +
  z_media_h:z_delta_q_7_60 +
  z_media_h:dia_semana +
  s(barrio, bs = "re") + s(segmento, bs = "re")

ajustar <- function(datos) {
  bam(
    formula_final,
    data = datos,
    family = binomial(),
    weights = n_clusters,
    method = "fREML",
    discrete = TRUE,
    nthreads = 2L
  )
}

predecir <- function(fit, datos, train) {
  segmentos_train <- levels(train$segmento)
  barrios_train <- levels(train$barrio)
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

metricas_fun <- function(dt) {
  error <- dt$predicho - dt$observado
  sse <- sum(error^2)
  sst <- sum((dt$observado - mean(dt$observado))^2)
  data.table(
    dias = nrow(dt),
    sesgo = mean(error),
    mae = mean(abs(error)),
    rmse = sqrt(mean(error^2)),
    correlacion = cor(dt$observado, dt$predicho),
    r2 = 1 - sse / sst
  )
}

if (ajustar_final && !solo_resumir) {
  cat("Ajustando modelo final\n")
  fit_final <- ajustar(train)
  saveRDS(fit_final, file.path(path_out, "modelo_final.rds"))

  resumen <- summary(fit_final)
  coef_final <- as.data.table(resumen$p.table, keep.rownames = "termino")
  setnames(
    coef_final, 2:5,
    c("estimacion", "error_std_convencional", "estadistico", "p_valor_convencional")
  )
  fwrite(coef_final, file.path(path_out, "coeficientes_convencionales.csv"))
  fwrite(data.table(
    convergio = isTRUE(fit_final$converged),
    AIC = AIC(fit_final),
    devianza_explicada = resumen$dev.expl,
    n_filas_train = nrow(train),
    n_segmentos_train = uniqueN(train$segmento),
    n_semanas_train = uniqueN(
      train$dia_objetivo - (as.integer(format(train$dia_objetivo, "%u")) - 1L)
    )
  ), file.path(path_out, "diagnostico_final.csv"))

  prob <- predecir(fit_final, base, train)
  pred <- copy(base[, .(
    dia_objetivo, split_modelo, observado, n_clusters
  )])
  pred[, pred_segmento := n_clusters * prob]
  pred_dia <- pred[, .(
    observado = sum(observado), predicho = sum(pred_segmento)
  ), by = .(split_modelo, dia_objetivo)]
  fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))

  metricas <- rbindlist(list(
    pred_dia[split_modelo %in% c("validacion", "test"),
      metricas_fun(.SD), by = split_modelo],
    pred_dia[split_modelo %in% c("validacion", "test"),
      metricas_fun(.SD)][, split_modelo := "validacion + test"]
  ), use.names = TRUE)
  fwrite(metricas, file.path(path_out, "metricas.csv"))
}

train[, `:=`(
  semana_inicio = dia_objetivo - (as.integer(format(dia_objetivo, "%u")) - 1L),
  segmento_original = as.character(segmento)
)]
semanas <- sort(unique(train$semana_inicio))
segmentos <- sort(unique(train$segmento_original))

if (ejecutar_boot && !solo_resumir) for (b in seq.int(boot_desde, boot_hasta)) {
  path_replica <- file.path(path_replicas, sprintf("replica_%03d.csv", b))
  if (file.exists(path_replica)) next
  set.seed(20260914 + b)

  muestra_semanas <- data.table(
    semana_inicio = sample(semanas, length(semanas), replace = TRUE),
    copia_semana = seq_along(semanas)
  )
  boot_temporal <- train[
    muestra_semanas, on = "semana_inicio", nomatch = 0L,
    allow.cartesian = TRUE
  ]

  muestra_segmentos <- data.table(
    segmento_original = sample(segmentos, length(segmentos), replace = TRUE),
    copia_segmento = seq_along(segmentos)
  )
  boot <- boot_temporal[
    muestra_segmentos, on = "segmento_original", nomatch = 0L,
    allow.cartesian = TRUE
  ]
  boot[, `:=`(
    segmento = factor(sprintf("segmento_boot_%04d", copia_segmento)),
    barrio = factor(as.character(barrio)),
    dia_semana = factor(as.character(dia_semana), levels = levels(train$dia_semana)),
    es_feriado = factor(as.character(es_feriado), levels = levels(train$es_feriado))
  )]

  cat("Bootstrap conjunto", b, "de", boot_hasta, "\n")
  resultado <- tryCatch({
    fit <- ajustar(boot)
    tabla <- as.data.table(summary(fit)$p.table, keep.rownames = "termino")
    setnames(
      tabla, 2:5,
      c("estimacion", "error_std_modelo", "estadistico", "p_valor_modelo")
    )
    tabla[, .(
      replica = b,
      termino,
      estimacion,
      error_std_modelo,
      convergio = isTRUE(fit$converged),
      error = NA_character_
    )]
  }, error = function(e) {
    data.table(
      replica = b, termino = NA_character_, estimacion = NA_real_,
      error_std_modelo = NA_real_, convergio = FALSE,
      error = conditionMessage(e)
    )
  })
  fwrite(resultado, path_replica)
}

archivos <- list.files(
  path_replicas, pattern = "^replica_[0-9]+[.]csv$", full.names = TRUE
)
if (length(archivos)) {
  boot_resultados <- rbindlist(lapply(archivos, fread), fill = TRUE)
  fwrite(boot_resultados, file.path(path_out, "bootstrap_coeficientes.csv"))

  boot_resumen <- boot_resultados[
    convergio == TRUE & !is.na(termino),
    .(
      n_replicas = .N,
      media_bootstrap = mean(estimacion),
      error_std_bootstrap = sd(estimacion),
      q025 = quantile(estimacion, .025),
      mediana = median(estimacion),
      q975 = quantile(estimacion, .975),
      proporcion_positiva = mean(estimacion > 0),
      proporcion_negativa = mean(estimacion < 0)
    ),
    by = termino
  ]

  path_coef <- file.path(path_out, "coeficientes_convencionales.csv")
  if (file.exists(path_coef)) {
    coef_final <- fread(path_coef)
    boot_resumen <- merge(
      coef_final[, .(termino, estimacion_original = estimacion,
        error_std_convencional)],
      boot_resumen,
      by = "termino",
      all.y = TRUE
    )
    boot_resumen[, razon_error_std :=
      error_std_bootstrap / error_std_convencional]
  }
  fwrite(boot_resumen, file.path(path_out, "bootstrap_resumen.csv"))
}

cat("\nMetricas finales:\n")
if (file.exists(file.path(path_out, "metricas.csv"))) {
  print(fread(file.path(path_out, "metricas.csv")))
}
cat("\nResumen bootstrap territorial y temporal:\n")
if (file.exists(file.path(path_out, "bootstrap_resumen.csv"))) {
  print(fread(file.path(path_out, "bootstrap_resumen.csv")))
}
