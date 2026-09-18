library(data.table)
library(xgboost)

# Sensibilidad del compacto actual a incorporar dia_semana en la correccion.
# es_feriado ya forma parte de ambas especificaciones. Al agregar dia_semana,
# los arboles pueden aprender efectos residuales e interacciones de calendario.

semillas_config <- Sys.getenv("SEMILLAS_XGB_CALENDARIO", unset = "")
semillas <- if (nzchar(semillas_config)) {
  as.integer(strsplit(semillas_config, ",", fixed = TRUE)[[1]])
} else {
  20260914:20260918
}
if (anyNA(semillas)) stop("SEMILLAS_XGB_CALENDARIO contiene valores no validos")

path_base <- file.path(
  "outputs", "comparacion_ventanas_propension_xgboost_com",
  "base_segmento_dia_ventanas.csv"
)
path_feriados <- file.path("data", "reference", "feriados", "feriados.R")
path_out <- "outputs/evaluacion_dia_semana_xgboost_com"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

env_feriados <- new.env(parent = baseenv())
sys.source(path_feriados, envir = env_feriados)
feriados <- sort(unique(as.IDate(env_feriados$diasDesc)))

base <- fread(path_base)
base[, dia_objetivo := as.IDate(dia_objetivo)]
base[, `:=`(
  dia_semana = factor(dia_semana),
  delta_q_7_60 = media_q_7 - media_q_60,
  es_feriado = as.integer(dia_objetivo %in% feriados)
)]

variables_compacto <- c(
  "media_tiempo_levante", "rms_q_7", "rms_w_7",
  "delta_q_7_60", "es_feriado"
)

especificaciones <- list(
  compacto_actual = list(dia_semana = FALSE),
  compacto_calendario = list(dia_semana = TRUE)
)

crear_matriz <- function(dt, incluir_dia_semana) {
  terminos <- c(
    if (incluir_dia_semana) "dia_semana" else character(),
    variables_compacto
  )
  model.matrix(as.formula(paste(
    "~", paste(terminos, collapse = " + "), "- 1"
  )), data = dt)
}

matrices <- lapply(especificaciones, function(spec) {
  crear_matriz(base, spec$dia_semana)
})

idx_fit <- which(
  base$split_modelo == "entrenamiento" &
    base$dia_objetivo < as.IDate("2025-11-01")
)
idx_es <- which(
  base$split_modelo == "entrenamiento" &
    base$dia_objetivo >= as.IDate("2025-11-01")
)
idx_train <- which(base$split_modelo == "entrenamiento")

construir_dmat <- function(X, idx) {
  d <- xgb.DMatrix(
    X[idx, , drop = FALSE],
    label = base$prop_reclamo[idx],
    weight = base$n_clusters[idx]
  )
  setinfo(d, "base_margin", base$margen_a0[idx])
  d
}

calcular_metricas <- function(pred_dia) {
  por_periodo <- pred_dia[
    split_modelo %in% c("validacion", "test"),
    {
      error <- predicho - observado
      .(
        dias = .N,
        sesgo = mean(error),
        mae = mean(abs(error)),
        rmse = sqrt(mean(error^2)),
        correlacion = cor(observado, predicho),
        razon_sd = sd(predicho) / sd(observado)
      )
    },
    by = split_modelo
  ]
  combinado <- pred_dia[
    split_modelo %in% c("validacion", "test"),
    {
      error <- predicho - observado
      .(
        split_modelo = "validacion + test",
        dias = .N,
        sesgo = mean(error),
        mae = mean(abs(error)),
        rmse = sqrt(mean(error^2)),
        correlacion = cor(observado, predicho),
        razon_sd = sd(predicho) / sd(observado)
      )
    }
  ]
  rbindlist(list(por_periodo, combinado), use.names = TRUE)
}

resultados_metricas <- list()
resultados_diagnostico <- list()
resultados_importancia <- list()
predicciones_referencia <- list()

for (semilla_actual in semillas) {
  for (nombre in names(especificaciones)) {
    X <- matrices[[nombre]]
    params <- list(
      objective = "binary:logistic",
      eval_metric = "logloss",
      eta = 0.03,
      max_depth = 3L,
      min_child_weight = 100,
      subsample = 0.80,
      colsample_bytree = 0.80,
      lambda = 10,
      alpha = 0,
      tree_method = "hist",
      nthread = 4L
    )

    set.seed(semilla_actual)
    dfit <- construir_dmat(X, idx_fit)
    des <- construir_dmat(X, idx_es)
    fit_es <- xgb.train(
      params = params,
      data = dfit,
      nrounds = 800L,
      watchlist = list(train = dfit, seleccion = des),
      early_stopping_rounds = 40L,
      verbose = 0
    )

    mejor_iter <- fit_es$best_iteration
    dtrain <- construir_dmat(X, idx_train)
    fit <- xgb.train(
      params = params,
      data = dtrain,
      nrounds = mejor_iter,
      verbose = 0
    )

    dnew <- xgb.DMatrix(X)
    setinfo(dnew, "base_margin", base$margen_a0)
    prob <- as.numeric(predict(fit, dnew))
    pred_segmento <- base[, .(
      split_modelo, dia_objetivo, n_clusters, observado
    )]
    pred_segmento[, prob_predicha := prob]
    pred_dia <- pred_segmento[, .(
      observado = sum(observado),
      predicho = sum(n_clusters * prob_predicha)
    ), by = .(split_modelo, dia_objetivo)]

    metricas <- calcular_metricas(pred_dia)
    metricas[, `:=`(semilla = semilla_actual, escenario = nombre)]
    resultados_metricas[[length(resultados_metricas) + 1L]] <- metricas

    importancia <- as.data.table(xgb.importance(model = fit))
    resultados_diagnostico[[length(resultados_diagnostico) + 1L]] <- data.table(
      semilla = semilla_actual,
      escenario = nombre,
      mejor_iteracion = mejor_iter,
      logloss_seleccion = fit_es$best_score,
      ganancia_dia_semana = sum(
        importancia[grepl("^dia_semana", Feature), Gain], na.rm = TRUE
      ),
      ganancia_feriado = sum(
        importancia[Feature == "es_feriado", Gain], na.rm = TRUE
      )
    )

    if (nombre == "compacto_calendario") {
      importancia[, `:=`(
        semilla = semilla_actual,
        escenario = nombre
      )]
      resultados_importancia[[length(resultados_importancia) + 1L]] <- importancia
    }

    if (semilla_actual == semillas[1]) {
      pred_dia[, `:=`(semilla = semilla_actual, escenario = nombre)]
      predicciones_referencia[[length(predicciones_referencia) + 1L]] <- pred_dia
    }
  }
}

metricas_semillas <- rbindlist(resultados_metricas)
diagnostico_semillas <- rbindlist(resultados_diagnostico)
importancia_semillas <- rbindlist(resultados_importancia, fill = TRUE)
predicciones_referencia <- rbindlist(predicciones_referencia)

deltas <- dcast(
  metricas_semillas,
  semilla + split_modelo ~ escenario,
  value.var = c("sesgo", "mae", "rmse", "correlacion", "razon_sd")
)
for (metrica in c("sesgo", "mae", "rmse", "correlacion", "razon_sd")) {
  deltas[, paste0("delta_", metrica) :=
    get(paste0(metrica, "_compacto_calendario")) -
      get(paste0(metrica, "_compacto_actual"))]
}

resumen_deltas <- deltas[, .(
  semillas = .N,
  delta_mae_media = mean(delta_mae),
  delta_mae_min = min(delta_mae),
  delta_mae_max = max(delta_mae),
  delta_rmse_media = mean(delta_rmse),
  delta_rmse_min = min(delta_rmse),
  delta_rmse_max = max(delta_rmse),
  mejora_rmse_semillas = sum(delta_rmse < 0),
  delta_correlacion_media = mean(delta_correlacion),
  delta_razon_sd_media = mean(delta_razon_sd)
), by = split_modelo]

fwrite(metricas_semillas, file.path(path_out, "metricas_semillas.csv"))
fwrite(deltas, file.path(path_out, "deltas_semillas.csv"))
fwrite(resumen_deltas, file.path(path_out, "resumen_deltas.csv"))
fwrite(diagnostico_semillas, file.path(path_out, "diagnostico_semillas.csv"))
fwrite(
  importancia_semillas,
  file.path(path_out, "importancia_calendario_semillas.csv")
)
fwrite(
  predicciones_referencia,
  file.path(path_out, "predicciones_diarias_semilla_referencia.csv")
)

print(resumen_deltas)
print(diagnostico_semillas[, .(
  ganancia_dia_semana_media = mean(ganancia_dia_semana),
  ganancia_dia_semana_min = min(ganancia_dia_semana),
  ganancia_dia_semana_max = max(ganancia_dia_semana),
  ganancia_feriado_media = mean(ganancia_feriado)
), by = escenario])
