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
path_modelos <- file.path("outputs", "modelo_inferencial_segmento_com")
path_out <- file.path(path_modelos, "exploracion_suavizados")
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
for (variable_actual in preparacion$variable) {
  p <- preparacion[match(variable_actual, preparacion[["variable"]])]
  x <- as.numeric(base[[variable_actual]])
  x[!is.finite(x)] <- NA_real_
  x[is.na(x)] <- p$mediana_train
  base[, paste0("z_", variable_actual) :=
    (x - p$media_train) / p$sd_train]
}

train <- droplevels(base[split_modelo == "entrenamiento"])
media_q7 <- mean(train$media_q_7, na.rm = TRUE)
sd_q7 <- sd(train$media_q_7, na.rm = TRUE)
base[, z_media_q_7 := (media_q_7 - media_q7) / sd_q7]
train <- droplevels(base[split_modelo == "entrenamiento"])

formula_base <- paste(
  "prop_reclamo ~ dia_semana + es_feriado +",
  "s(z_log_densidad_pob, k = 5) +",
  "s(z_porc_nbi_segmento, k = 5) +",
  "s(z_media_h, k = 6) +",
  "PROPENSION +",
  "s(z_delta_q_7_60, k = 6) +",
  "INTERACCION +",
  "z_media_h:dia_semana + z_media_h:es_feriado +",
  "s(barrio, bs = 're') + s(segmento, bs = 're')"
)

crear_formula <- function(propension, interaccion) {
  texto <- sub("PROPENSION", propension, formula_base, fixed = TRUE)
  texto <- sub("INTERACCION", interaccion, texto, fixed = TRUE)
  as.formula(texto)
}

formulas_aditivas <- list(
  S60_aditivo = crear_formula(
    "s(z_media_q_60, k = 6)", "z_media_h:z_delta_q_7_60"
  ),
  S7_aditivo = crear_formula(
    "s(z_media_q_7, k = 6)", "z_media_h:z_delta_q_7_60"
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
    select = TRUE,
    nthreads = 2L
  )
}

predecir <- function(fit, datos) {
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
  data.table(
    dias = nrow(dt),
    sesgo = mean(error),
    mae = mean(abs(error)),
    rmse = sqrt(mean(error^2)),
    correlacion = cor(dt$observado, dt$predicho)
  )
}

ajustes <- list()
predicciones <- list()
diagnosticos <- list()
suavizados <- list()

procesar_ajuste <- function(escenario, formula) {
  cat("Ajustando", escenario, "\n")
  fit <- ajustar(formula)
  prob <- predecir(fit, base)
  pred <- base[, .(
    dia_objetivo, split_modelo, observado, n_clusters
  )]
  pred[, pred_segmento := n_clusters * prob]
  pred <- pred[, .(
    observado = sum(observado),
    predicho = sum(pred_segmento)
  ), by = .(split_modelo, dia_objetivo)]
  pred[, escenario := escenario]

  resumen <- summary(fit)
  tabla_s <- as.data.table(resumen$s.table, keep.rownames = "termino")
  setnames(tabla_s, 2:5, c("edf", "ref_df", "estadistico", "p_valor"))
  tabla_s[, escenario := escenario]

  list(
    fit = fit,
    pred = pred,
    diagnostico = data.table(
      escenario = escenario,
      convergio = isTRUE(fit$converged),
      AIC = AIC(fit),
      devianza_explicada = resumen$dev.expl
    ),
    suavizados = tabla_s
  )
}

for (escenario in names(formulas_aditivas)) {
  resultado <- procesar_ajuste(escenario, formulas_aditivas[[escenario]])
  ajustes[[escenario]] <- resultado$fit
  predicciones[[escenario]] <- resultado$pred
  diagnosticos[[escenario]] <- resultado$diagnostico
  suavizados[[escenario]] <- resultado$suavizados
}

pred_aditivos <- rbindlist(predicciones)
metricas_aditivas <- rbindlist(list(
  pred_aditivos[split_modelo %in% c("validacion", "test"),
    metricas_fun(.SD), by = .(escenario, split_modelo)],
  pred_aditivos[split_modelo %in% c("validacion", "test"),
    metricas_fun(.SD), by = escenario][, split_modelo := "validacion + test"]
), use.names = TRUE)

ganador <- metricas_aditivas[
  split_modelo == "validacion + test"
][order(rmse), escenario][1L]
propension_ganadora <- if (ganador == "S7_aditivo") {
  "s(z_media_q_7, k = 6)"
} else {
  "s(z_media_q_60, k = 6)"
}
nombre_tensor <- if (ganador == "S7_aditivo") "S7_tensor_delta" else "S60_tensor_delta"
formula_tensor <- crear_formula(
  propension_ganadora,
  "ti(z_media_h, z_delta_q_7_60, k = c(5, 5))"
)

resultado_tensor <- procesar_ajuste(nombre_tensor, formula_tensor)
ajustes[[nombre_tensor]] <- resultado_tensor$fit
predicciones[[nombre_tensor]] <- resultado_tensor$pred
diagnosticos[[nombre_tensor]] <- resultado_tensor$diagnostico
suavizados[[nombre_tensor]] <- resultado_tensor$suavizados

pred_todos <- rbindlist(predicciones)
metricas <- rbindlist(list(
  pred_todos[split_modelo %in% c("validacion", "test"),
    metricas_fun(.SD), by = .(escenario, split_modelo)],
  pred_todos[split_modelo %in% c("validacion", "test"),
    metricas_fun(.SD), by = escenario][, split_modelo := "validacion + test"]
), use.names = TRUE)

mensual <- pred_todos[split_modelo %in% c("validacion", "test"),
  metricas_fun(.SD),
  by = .(escenario, mes = format(dia_objetivo, "%Y-%m"))]

lineal <- fread(file.path(path_modelos, "prueba_interaccion_delta_metricas.csv"))[
  escenario == "I4_delta"
]
lineal[, escenario := "L_delta_lineal"]
metricas <- rbindlist(list(metricas, lineal), use.names = TRUE, fill = TRUE)

fwrite(metricas, file.path(path_out, "metricas.csv"))
fwrite(mensual, file.path(path_out, "metricas_mensuales.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnosticos.csv"))
fwrite(rbindlist(suavizados, fill = TRUE), file.path(path_out, "suavizados_edf.csv"))
fwrite(pred_todos, file.path(path_out, "predicciones_diarias.csv"))
saveRDS(
  list(
    ganador_aditivo = ganador,
    modelo_tensor = nombre_tensor,
    formulas = c(formulas_aditivas, setNames(list(formula_tensor), nombre_tensor))
  ),
  file.path(path_out, "definiciones_modelos.rds")
)

cat("\nGanador aditivo:", ganador, "\n")
cat("\nDiagnosticos:\n")
print(rbindlist(diagnosticos)[order(AIC)])
cat("\nGrados de libertad de los suavizados:\n")
print(rbindlist(suavizados, fill = TRUE)[, .(escenario, termino, edf)])
cat("\nMetricas:\n")
print(metricas[order(split_modelo, rmse)])
cat("\nMetricas mensuales:\n")
print(mensual[order(mes, rmse)])
