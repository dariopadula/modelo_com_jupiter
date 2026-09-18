library(arrow)
library(data.table)
library(mgcv)

set.seed(20260915)

path_base <- file.path(
  "outputs", "comparacion_ventanas_propension_xgboost_com",
  "base_segmento_dia_ventanas.csv"
)
path_territorio <- file.path(
  "data", "processed", "cluster_territorial", "cluster_segmento_censal"
)
path_feriados <- file.path("data", "reference", "feriados", "feriados.R")
path_clima <- file.path(
  "data", "processed", "clima", "inumet_melilla_g3",
  "clima_inumet_melilla_g3_features_diarias.csv"
)
path_viento <- file.path(
  "data", "raw", "inumet", "datos_abiertos",
  "inumet_intensidad_de_viento.csv"
)
path_modelos <- file.path("outputs", "modelo_inferencial_segmento_com")
path_out <- file.path(path_modelos, "exploracion_clima_d1")
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

estacion_fuente <- "Aeropuerto Melilla G3"

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

# Temperatura y precipitacion ya estan cerradas en D-1. Para esta prueba se
# conservan solo dias con las 24 observaciones horarias del dia anterior.
clima <- fread(path_clima)
clima[, dia_objetivo := as.IDate(dia)]
clima <- clima[
  horas_temp_validas_d1 == 24L & horas_prec_validas_d1 == 24L,
  .(
    dia_objetivo,
    temp_media_d1_c,
    precipitacion_d1_mm,
    lluvia_ge1_d1 = factor(
      as.integer(precipitacion_d1_mm >= 1),
      levels = c(0, 1)
    ),
    log_precipitacion_d1 = log1p(precipitacion_d1_mm)
  )
]

# El viento se observa normalmente cada dos horas. Se agrega el dia observado
# y se desplaza una jornada para que la fila objetivo D use solamente D-1.
viento <- fread(
  path_viento,
  sep = ";",
  na.strings = c("", "NA"),
  encoding = "UTF-8"
)
viento <- viento[
  estacion_id == estacion_fuente & !is.na(fecha) & !is.na(int_viento)
]
viento[, fecha_hora := as.POSIXct(
  fecha,
  format = "%Y-%m-%d %H:%M",
  tz = "America/Montevideo"
)]
viento[, dia_observado := as.IDate(fecha_hora, tz = "America/Montevideo")]
viento_diario <- viento[, .(
  viento_media_d1_kmh = mean(as.numeric(int_viento)),
  viento_max_d1_kmh = max(as.numeric(int_viento)),
  n_obs_viento_d1 = .N
), by = dia_observado]
viento_diario <- viento_diario[n_obs_viento_d1 == 12L]
viento_diario[, dia_objetivo := dia_observado + 1L]
viento_diario[, dia_observado := NULL]

clima <- merge(clima, viento_diario, by = "dia_objetivo", all = FALSE)
base <- merge(base, clima, by = "dia_objetivo", all.x = TRUE, sort = FALSE)

variables_clima <- c(
  "temp_media_d1_c", "precipitacion_d1_mm", "lluvia_ge1_d1",
  "log_precipitacion_d1", "viento_media_d1_kmh", "viento_max_d1_kmh"
)
dias_cobertura <- unique(base[, c("dia_objetivo", "split_modelo", variables_clima), with = FALSE])
dias_cobertura[, clima_completo := complete.cases(.SD), .SDcols = variables_clima]
cobertura <- dias_cobertura[, .(
  dias_totales = .N,
  dias_clima_completo = sum(clima_completo),
  dias_excluidos = sum(!clima_completo)
), by = split_modelo]
fwrite(cobertura, file.path(path_out, "cobertura_por_split.csv"))

dias_validos <- dias_cobertura[clima_completo == TRUE, dia_objetivo]
base <- base[dia_objetivo %in% dias_validos]
train <- droplevels(base[split_modelo == "entrenamiento"])

formula_referencia <- prop_reclamo ~
  dia_semana + es_feriado +
  z_log_densidad_pob + z_porc_nbi_segmento +
  z_media_h + z_media_q_60 + z_delta_q_7_60 +
  z_media_h:z_delta_q_7_60 +
  z_media_h:dia_semana +
  s(barrio, bs = "re") + s(segmento, bs = "re")

formulas <- list(
  referencia = formula_referencia,
  temperatura_d1 = update(
    formula_referencia,
    . ~ . + s(temp_media_d1_c, bs = "cr", k = 5)
  ),
  lluvia_d1 = update(
    formula_referencia,
    . ~ . + lluvia_ge1_d1 +
      s(log_precipitacion_d1, bs = "cr", k = 4)
  ),
  viento_d1 = update(
    formula_referencia,
    . ~ . + s(viento_media_d1_kmh, bs = "cr", k = 4)
  ),
  viento_max_d1 = update(
    formula_referencia,
    . ~ . + s(viento_max_d1_kmh, bs = "cr", k = 4)
  ),
  clima_d1_completo = update(
    formula_referencia,
    . ~ . +
      s(temp_media_d1_c, bs = "cr", k = 5) +
      lluvia_ge1_d1 +
      s(log_precipitacion_d1, bs = "cr", k = 4) +
      s(viento_media_d1_kmh, bs = "cr", k = 4)
  ),
  clima_d1_viento_max = update(
    formula_referencia,
    . ~ . +
      s(temp_media_d1_c, bs = "cr", k = 5) +
      lluvia_ge1_d1 +
      s(log_precipitacion_d1, bs = "cr", k = 4) +
      s(viento_max_d1_kmh, bs = "cr", k = 4)
  )
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
      fit,
      newdata = nd,
      type = "response",
      exclude = "s(segmento)"
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

ajustes <- list()
predicciones <- list()
diagnosticos <- list()
parametricos <- list()
suavizados <- list()

for (nombre in names(formulas)) {
  cat("Ajustando", nombre, "\n")
  fit <- bam(
    formulas[[nombre]],
    data = train,
    family = binomial(),
    weights = n_clusters,
    method = "fREML",
    discrete = TRUE,
    nthreads = 2L
  )
  ajustes[[nombre]] <- fit
  resumen <- summary(fit)

  diagnosticos[[nombre]] <- data.table(
    modelo = nombre,
    convergio = isTRUE(fit$converged),
    AIC = AIC(fit),
    devianza_explicada_train = resumen$dev.expl,
    n_filas_train = nrow(train),
    n_dias_train = uniqueN(train$dia_objetivo)
  )

  tabla_p <- as.data.table(resumen$p.table, keep.rownames = "termino")
  setnames(tabla_p, 2:5, c("estimacion", "error_std", "estadistico", "p_valor"))
  tabla_p[, modelo := nombre]
  parametricos[[nombre]] <- tabla_p

  if (!is.null(resumen$s.table)) {
    tabla_s <- as.data.table(resumen$s.table, keep.rownames = "termino")
    setnames(
      tabla_s,
      2:5,
      c("edf", "ref_df", "estadistico", "p_valor")
    )
    tabla_s[, modelo := nombre]
    suavizados[[nombre]] <- tabla_s
  }

  prob <- predecir(fit, base, train)
  pred <- copy(base[, .(
    dia_objetivo, split_modelo, observado, n_clusters,
    temp_media_d1_c, precipitacion_d1_mm,
    viento_media_d1_kmh, viento_max_d1_kmh
  )])
  pred[, `:=`(modelo = nombre, pred_segmento = n_clusters * prob)]
  predicciones[[nombre]] <- pred[, .(
    observado = sum(observado),
    predicho = sum(pred_segmento),
    temp_media_d1_c = first(temp_media_d1_c),
    precipitacion_d1_mm = first(precipitacion_d1_mm),
    viento_media_d1_kmh = first(viento_media_d1_kmh),
    viento_max_d1_kmh = first(viento_max_d1_kmh)
  ), by = .(modelo, split_modelo, dia_objetivo)]
}

pred_dia <- rbindlist(predicciones)
metricas <- rbindlist(list(
  pred_dia[
    split_modelo %in% c("validacion", "test"),
    metricas_fun(.SD),
    by = .(modelo, split_modelo)
  ],
  pred_dia[
    split_modelo %in% c("validacion", "test"),
    metricas_fun(.SD),
    by = modelo
  ][, split_modelo := "validacion + test"]
), use.names = TRUE)

fwrite(metricas, file.path(path_out, "metricas.csv"))
fwrite(pred_dia, file.path(path_out, "predicciones_diarias.csv"))
fwrite(rbindlist(diagnosticos), file.path(path_out, "diagnosticos_modelos.csv"))
fwrite(rbindlist(parametricos, fill = TRUE), file.path(path_out, "terminos_parametricos.csv"))
fwrite(rbindlist(suavizados, fill = TRUE), file.path(path_out, "terminos_suavizados.csv"))

cat("\nCobertura comun:\n")
print(cobertura)
cat("\nMetricas exploratorias:\n")
print(metricas[order(split_modelo, rmse)])
cat("\nTerminos climaticos de los modelos completos:\n")
print(rbindlist(suavizados, fill = TRUE)[
  modelo %chin% c("clima_d1_completo", "clima_d1_viento_max") &
    grepl("temp_media|precipitacion|viento", termino)
])
