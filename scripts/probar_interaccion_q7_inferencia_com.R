library(arrow)
library(data.table)
library(mgcv)

tipo_interaccion <- Sys.getenv("TIPO_INTERACCION", "q7")
if (!tipo_interaccion %in% c("q7", "delta")) {
  stop("TIPO_INTERACCION debe ser q7 o delta")
}

path_base <- file.path(
  "outputs", "comparacion_ventanas_propension_xgboost_com",
  "base_segmento_dia_ventanas.csv"
)
path_territorio <- file.path(
  "data", "processed", "cluster_territorial", "cluster_segmento_censal"
)
path_feriados <- file.path("data", "reference", "feriados", "feriados.R")
path_modelos <- file.path("outputs", "modelo_inferencial_segmento_com")

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
  porc_nbi_segmento = first(porc_nbi_segmento),
  densidad_pob_km2 = first(densidad_pob_km2)
), by = segmento]

base[territorio, on = "segmento", `:=`(
  porc_nbi_segmento = i.porc_nbi_segmento,
  densidad_pob_km2 = i.densidad_pob_km2
)]
base[, `:=`(
  log_densidad_pob = log1p(densidad_pob_km2),
  es_feriado = factor(as.integer(dia_objetivo %in% feriados)),
  prop_reclamo = observado / n_clusters,
  dia_semana = factor(dia_semana),
  barrio = factor(barrio),
  segmento = factor(segmento)
)]

preparacion <- fread(file.path(path_modelos, "preparacion_variables.csv"))
variables_originales <- preparacion$variable
for (variable in variables_originales) {
  indice <- match(variable, preparacion[["variable"]])
  p <- preparacion[indice]
  x <- as.numeric(base[[variable]])
  x[!is.finite(x)] <- NA_real_
  x[is.na(x)] <- p$mediana_train
  base[, paste0("z_", variable) := (x - p$media_train) / p$sd_train]
}

train <- droplevels(base[split_modelo == "entrenamiento"])
media_q7 <- mean(train$media_q_7, na.rm = TRUE)
sd_q7 <- sd(train$media_q_7, na.rm = TRUE)
base[, z_media_q_7 := (media_q_7 - media_q7) / sd_q7]
train <- droplevels(base[split_modelo == "entrenamiento"])

termino_interaccion <- if (tipo_interaccion == "q7") {
  "z_media_h:z_media_q_7"
} else {
  "z_media_h:z_delta_q_7_60"
}
formula_variante <- as.formula(paste(
  "prop_reclamo ~ dia_semana + es_feriado +",
  "z_log_densidad_pob + z_porc_nbi_segmento +",
  "z_media_h + z_media_q_60 + z_delta_q_7_60 +",
  termino_interaccion, "+",
  "z_media_h:dia_semana + z_media_h:es_feriado +",
  "s(barrio, bs = 're') + s(segmento, bs = 're')"
))

fit_variante <- bam(
  formula_variante,
  data = train,
  family = binomial(),
  weights = n_clusters,
  method = "fREML",
  discrete = TRUE,
  nthreads = 2L
)

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

prob_variante <- predecir(fit_variante, base, train)
pred_variante <- copy(base[, .(dia_objetivo, split_modelo, observado, n_clusters)])
pred_variante[, pred_segmento := n_clusters * prob_variante]
pred_variante <- pred_variante[, .(
  observado = sum(observado), predicho = sum(pred_segmento)
), by = .(split_modelo, dia_objetivo)]

pred_actual <- fread(file.path(path_modelos, "predicciones_diarias.csv"))[
  escenario == "I4_calendario",
  .(split_modelo, dia_objetivo = as.IDate(dia_objetivo), observado, predicho)
]

calcular_metricas <- function(dt) {
  error <- dt$predicho - dt$observado
  data.table(
    dias = nrow(dt),
    sesgo = mean(error),
    mae = mean(abs(error)),
    rmse = sqrt(mean(error^2)),
    correlacion = cor(dt$observado, dt$predicho)
  )
}

pred_comparacion <- rbindlist(list(
  pred_actual[, escenario := "I4_q60"],
  pred_variante[, escenario := paste0("I4_", tipo_interaccion)]
), use.names = TRUE)

metricas_periodo <- pred_comparacion[
  split_modelo %in% c("validacion", "test"),
  calcular_metricas(.SD),
  by = .(escenario, split_modelo)
]
metricas_total <- pred_comparacion[
  split_modelo %in% c("validacion", "test"),
  calcular_metricas(.SD),
  by = escenario
][, split_modelo := "validacion + test"]
metricas <- rbindlist(list(metricas_periodo, metricas_total), use.names = TRUE)

tabla_coef <- as.data.table(summary(fit_variante)$p.table, keep.rownames = "termino")
setnames(tabla_coef, 2:5, c("estimacion", "error_std", "estadistico", "p_valor"))
coef_interaccion <- tabla_coef[termino == termino_interaccion]

resultado <- list(
  tipo_interaccion = tipo_interaccion,
  convergio = isTRUE(fit_variante$converged),
  AIC = AIC(fit_variante),
  devianza_explicada = summary(fit_variante)$dev.expl,
  media_q7_train = media_q7,
  sd_q7_train = sd_q7,
  coef_interaccion = coef_interaccion,
  metricas = metricas
)

saveRDS(
  resultado,
  file.path(path_modelos, paste0(
    "prueba_interaccion_", tipo_interaccion, "_resultado.rds"
  ))
)
fwrite(
  metricas,
  file.path(path_modelos, paste0(
    "prueba_interaccion_", tipo_interaccion, "_metricas.csv"
  ))
)

cat("Interaccion", tipo_interaccion, ":\n")
print(coef_interaccion)
cat("\nAIC y devianza explicada:\n")
print(data.table(
  escenario = paste0("I4_", tipo_interaccion), AIC = AIC(fit_variante),
  devianza_explicada = summary(fit_variante)$dev.expl
))
cat("\nMetricas:\n")
print(metricas[order(split_modelo, rmse)])
