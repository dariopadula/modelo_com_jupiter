library(arrow)
library(data.table)
library(dplyr)
library(mgcv)

source("funciones/splits_temporales.R")

path_base <- "data/processed/features_compartidas/segmento_dia"
path_actual <- paste0(
  "data/processed/modelos/reevaluacion_2026/agregados_inferencia/",
  "predicciones_diarias_validacion.csv"
)
path_out <- paste0(
  "outputs/reevaluacion_2026/",
  "exploracion_inferencia_curvatura_interaccion_q30_delta"
)
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base <- as.data.table(as.data.frame(
  arrow::open_dataset(path_base, format = "parquet") |>
    dplyr::filter(dia <= as.Date("2026-06-30")) |>
    dplyr::collect()
))
base[, dia := as.IDate(dia)]
base <- asignar_split_congelado(base)
base <- base[split %in% c("entrenamiento", "validacion")]
base[, `:=`(
  prop_reclamo = observado / n_clusters,
  dia_semana = factor(dia_semana),
  es_feriado = factor(as.integer(es_feriado)),
  barrio = factor(barrio),
  segmento = factor(segmento)
)]

variables_continuas <- c(
  "log_densidad_pob", "porc_nbi_segmento", "media_h",
  "media_q_30", "delta_q_7_30"
)
train_inicial <- base[split == "entrenamiento"]
preparacion <- rbindlist(lapply(variables_continuas, function(variable) {
  x <- train_inicial[[variable]]
  mediana <- median(x[is.finite(x)], na.rm = TRUE)
  x[!is.finite(x)] <- mediana
  data.table(
    variable = variable,
    mediana_train = mediana,
    media_train = mean(x),
    sd_train = sd(x)
  )
}))

for (variable in variables_continuas) {
  p <- preparacion[match(variable, preparacion[["variable"]])]
  x <- base[[variable]]
  x[!is.finite(x)] <- p$mediana_train
  base[, paste0("z_", variable) := (x - p$media_train) / p$sd_train]
}
base[, z_delta_q_7_30_sq := z_delta_q_7_30^2]

train <- droplevels(base[split == "entrenamiento"])
valid <- base[split == "validacion"]
valid[, `:=`(
  dia_semana = factor(dia_semana, levels = levels(train$dia_semana)),
  es_feriado = factor(es_feriado, levels = levels(train$es_feriado)),
  barrio = factor(barrio, levels = levels(train$barrio)),
  segmento = factor(segmento, levels = levels(train$segmento))
)]

formula_base <- prop_reclamo ~
  dia_semana + es_feriado + sin_anual + cos_anual +
  z_log_densidad_pob + z_porc_nbi_segmento +
  z_media_h + z_media_q_30 + z_delta_q_7_30 +
  z_media_h:z_delta_q_7_30 + z_media_h:dia_semana +
  s(barrio, bs = "re") + s(segmento, bs = "re")

formulas <- list(
  inferencial_delta_cuadratico = update(
    formula_base, . ~ . + z_delta_q_7_30_sq
  ),
  inferencial_delta_cuadratico_sin_h_delta = update(
    formula_base,
    . ~ . + z_delta_q_7_30_sq - z_media_h:z_delta_q_7_30
  ),
  inferencial_q30_por_delta = update(
    formula_base, . ~ . + z_media_q_30:z_delta_q_7_30
  )
)

ajustar <- function(formula) {
  bam(
    formula,
    data = train,
    family = binomial(),
    weights = n_clusters,
    method = "fREML",
    discrete = TRUE,
    nthreads = 1L
  )
}

set.seed(20260917L)
fits <- lapply(formulas, ajustar)
if (!all(vapply(fits, function(x) isTRUE(x$converged), logical(1)))) {
  stop("Al menos uno de los modelos exploratorios no convergio")
}

pred_nuevas <- rbindlist(lapply(names(fits), function(nombre) {
  prob <- as.numeric(predict(fits[[nombre]], newdata = valid, type = "response"))
  pred_segmento <- copy(valid)
  pred_segmento[, prob_predicha := prob]
  pred_segmento[, .(
    observado = sum(observado),
    predicho = sum(n_clusters * prob_predicha),
    n_clusters_total = sum(n_clusters)
  ), by = dia][, candidato := nombre]
}))

pred_actual <- fread(path_actual)[candidato == "inferencial_q30_ciclo"]
pred_actual[, dia := as.IDate(dia)]
totales_dia <- valid[, .(n_clusters_total = sum(n_clusters)), by = dia]
pred_actual <- totales_dia[pred_actual, on = "dia"]
predicciones <- rbindlist(list(
  pred_actual[, .(dia, candidato, observado, predicho, n_clusters_total)],
  pred_nuevas[, .(dia, candidato, observado, predicho, n_clusters_total)]
))

calcular_metricas <- function(dt) {
  error <- dt$predicho - dt$observado
  sst <- sum((dt$observado - mean(dt$observado))^2)
  data.table(
    dias = nrow(dt),
    media_observada = mean(dt$observado),
    media_predicha = mean(dt$predicho),
    sesgo = mean(error),
    mae = mean(abs(error)),
    rmse = sqrt(mean(error^2)),
    correlacion = cor(dt$observado, dt$predicho),
    r2 = 1 - sum(error^2) / sst
  )
}

metricas <- predicciones[, calcular_metricas(.SD), by = candidato]
predicciones[, anio_mes := as.integer(format(dia, "%Y%m"))]
metricas_mes <- predicciones[, calcular_metricas(.SD), by = .(candidato, anio_mes)]

pred_nuevas_wide <- dcast(
  predicciones[candidato %in% c(
    "inferencial_delta_cuadratico", "inferencial_q30_por_delta"
  )],
  dia ~ candidato,
  value.var = "predicho"
)
comparacion_nuevas <- data.table(
  correlacion_predicciones = cor(
    pred_nuevas_wide$inferencial_delta_cuadratico,
    pred_nuevas_wide$inferencial_q30_por_delta
  ),
  diferencia_absoluta_media = mean(abs(
    pred_nuevas_wide$inferencial_delta_cuadratico -
      pred_nuevas_wide$inferencial_q30_por_delta
  )),
  diferencia_absoluta_maxima = max(abs(
    pred_nuevas_wide$inferencial_delta_cuadratico -
      pred_nuevas_wide$inferencial_q30_por_delta
  ))
)

coeficientes <- rbindlist(lapply(names(fits), function(nombre) {
  tabla <- as.data.table(summary(fits[[nombre]])$p.table, keep.rownames = "termino")
  tabla[, candidato := nombre]
  setcolorder(tabla, c("candidato", "termino"))
  tabla
}), fill = TRUE)

ajuste_train <- rbindlist(lapply(names(fits), function(nombre) {
  fit <- fits[[nombre]]
  data.table(
    candidato = nombre,
    log_likelihood = as.numeric(logLik(fit)),
    aic = AIC(fit),
    devianza_explicada = summary(fit)$dev.expl,
    convergio = isTRUE(fit$converged)
  )
}))

saveRDS(list(
  fits = fits,
  formulas = formulas,
  formula_base = formula_base,
  preparacion = preparacion,
  version_split = "reevaluacion_2026_v1",
  usa_test = FALSE,
  bootstrap = FALSE
), file.path(path_out, "modelos_exploratorios.rds"))
fwrite(predicciones, file.path(path_out, "predicciones_validacion.csv"))
fwrite(metricas, file.path(path_out, "metricas_validacion.csv"))
fwrite(metricas_mes, file.path(path_out, "metricas_validacion_mes.csv"))
fwrite(coeficientes, file.path(path_out, "coeficientes.csv"))
fwrite(ajuste_train, file.path(path_out, "ajuste_train.csv"))
fwrite(preparacion, file.path(path_out, "preparacion_variables.csv"))
fwrite(comparacion_nuevas, file.path(path_out, "comparacion_predicciones.csv"))

print(metricas[order(rmse)])
print(metricas_mes[order(anio_mes, rmse)])
print(coeficientes[termino %in% c(
  "z_delta_q_7_30_sq", "z_media_q_30:z_delta_q_7_30"
)])
