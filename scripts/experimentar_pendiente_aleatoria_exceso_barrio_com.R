library(data.table)
library(mgcv)

path_base <- file.path(
  "outputs", "experimento_modelos_agregados_m0_m4_com",
  "base_territorio_dia_con_ratio.csv"
)
path_out <- file.path(
  "outputs", "experimento_pendiente_aleatoria_exceso_barrio_com"
)
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

base <- fread(path_base)
base <- base[nivel_territorial == "barrio"]
base[, `:=`(
  territorio = factor(territorio),
  dia_semana = factor(dia_semana),
  mes = factor(mes)
)]

# La referencia habitual de cada barrio se aprende exclusivamente en train.
referencia_barrio <- base[
  split_modelo == "entrenamiento",
  .(exceso_habitual_barrio = mean(carga_exceso_media, na.rm = TRUE)),
  by = territorio
]
base[referencia_barrio, exceso_habitual_barrio := i.exceso_habitual_barrio,
     on = "territorio"]
base[, exceso_desviacion_diaria := carga_exceso_media - exceso_habitual_barrio]

estandarizar_train <- function(dt, variable, nombre_z) {
  x_train <- dt[split_modelo == "entrenamiento", get(variable)]
  mediana <- median(x_train, na.rm = TRUE)
  x_train[!is.finite(x_train)] <- mediana
  media <- mean(x_train)
  desvio <- sd(x_train)
  if (!is.finite(desvio) || desvio == 0) desvio <- 1
  x <- dt[[variable]]
  x[!is.finite(x)] <- mediana
  dt[, (nombre_z) := (x - media) / desvio]
  data.table(
    variable = variable, mediana_train = mediana,
    media_train = media, desvio_train = desvio
  )
}

prep_exceso <- rbindlist(list(
  estandarizar_train(base, "exceso_habitual_barrio", "z_exceso_habitual_barrio"),
  estandarizar_train(base, "exceso_desviacion_diaria", "z_exceso_desviacion_diaria")
))

formula_base <- prop_clusters_reclamo ~ dia_semana + mes +
  z_score_medio + z_score_sd + z_score_p90 +
  z_tiempo_levante_medio + z_tiempo_levante_p90 + z_pct_clusters_tiempo_3omas +
  z_contenedores_activos_medio + z_pct_inferidos_medio +
  z_reclamos_lag1_medio + z_reclamos_7d_medio + z_reclamos_30d_medio +
  s(territorio, bs = "re")

formulas <- list(
  B0_sin_exceso = formula_base,
  B1_exceso_fijo = update(
    formula_base,
    . ~ . + z_exceso_habitual_barrio + z_exceso_desviacion_diaria
  ),
  B2_pendiente_aleatoria = update(
    formula_base,
    . ~ . + z_exceso_habitual_barrio + z_exceso_desviacion_diaria +
      s(territorio, by = z_exceso_desviacion_diaria, bs = "re")
  )
)

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
  prob <- as.numeric(predict.gam(fit, newdata = newdata, type = "response"))
  pred <- base[, .(
    dia_objetivo, split_modelo, territorio, n_clusters,
    clusters_con_reclamo, suma_scores
  )]
  pred[, `:=`(
    escenario = escenario,
    prob_predicha = prob,
    clusters_esperados = n_clusters * prob
  )]
  fits[[escenario]] <- fit
  predicciones[[escenario]] <- pred
  resumen_smooth <- summary(fit)$s.table
  diagnosticos[[escenario]] <- data.table(
    escenario = escenario,
    convergencia = if (isTRUE(fit$converged)) "OK" else "REVISAR",
    AIC = AIC(fit),
    logLik = as.numeric(logLik(fit)),
    n_coeficientes = length(coef(fit)),
    edf_intercepto_barrio = resumen_smooth["s(territorio)", "edf"],
    edf_pendiente_barrio = if (
      "s(territorio):z_exceso_desviacion_diaria" %in% rownames(resumen_smooth)
    ) resumen_smooth["s(territorio):z_exceso_desviacion_diaria", "edf"] else NA_real_
  )
}

pred <- rbindlist(predicciones)
pred_dia <- pred[, .(
  observado = sum(clusters_con_reclamo),
  predicho = sum(clusters_esperados),
  suma_scores = sum(suma_scores)
), by = .(dia_objetivo, split_modelo, escenario)]

metricas <- pred_dia[split_modelo %in% c("validacion", "test"), {
  error <- predicho - observado
  .(
    dias = .N,
    media_observada = mean(observado),
    media_predicha = mean(predicho),
    sesgo = mean(error),
    mae = mean(abs(error)),
    rmse = sqrt(mean(error^2)),
    correlacion = cor(observado, predicho),
    sd_observado = sd(observado),
    sd_predicho = sd(predicho),
    razon_sd = sd(predicho) / sd(observado)
  )
}, by = .(escenario, periodo = split_modelo)]

for (escenario in names(fits)) {
  saveRDS(fits[[escenario]], file.path(path_out, paste0("modelo_", escenario, ".rds")))
}
fwrite(base, file.path(path_out, "base_barrio_dia_exceso_centrado.csv"))
fwrite(prep_exceso, file.path(path_out, "preparacion_exceso.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(metricas, file.path(path_out, "metricas.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnostico_modelos.csv"))

print(rbindlist(diagnosticos))
print(metricas[periodo == "test"])
