library(arrow)
library(data.table)

base_dir <- "data/processed/modelos/experimentos_exceso_levante"
out_dir <- "outputs/experimentos_exceso_levante"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

leer_dataset <- function(path) {
  as.data.table(arrow::open_dataset(path, format = "parquet"))
}

modelos <- list(
  list(modelo = "xgboost_com", variante = "base", path = file.path(base_dir, "xgboost_com_base")),
  list(modelo = "xgboost_com", variante = "base_exceso_levante", path = file.path(base_dir, "xgboost_com_base_exceso_levante")),
  list(modelo = "logistico_reducido", variante = "base", path = file.path(base_dir, "logistico_reducido_base")),
  list(modelo = "logistico_reducido", variante = "base_exceso_levante", path = file.path(base_dir, "logistico_reducido_base_exceso_levante"))
)

metricas <- rbindlist(lapply(modelos, function(cfg) {
  dt <- leer_dataset(file.path(cfg$path, "metricas"))
  dt[, `:=`(modelo = cfg$modelo, variante = cfg$variante)]
  dt
}), fill = TRUE)

metricas_base <- metricas[variante == "base", .(
  modelo,
  split,
  auc_base = auc,
  logloss_base = logloss
)]

metricas_delta <- metricas[
  variante == "base_exceso_levante",
  .(modelo, split, auc_exceso = auc, logloss_exceso = logloss)
][
  metricas_base,
  on = c("modelo", "split")
]
metricas_delta[, `:=`(
  delta_auc = auc_exceso - auc_base,
  delta_logloss = logloss_exceso - logloss_base
)]
setcolorder(metricas_delta, c(
  "modelo",
  "split",
  "auc_base",
  "auc_exceso",
  "delta_auc",
  "logloss_base",
  "logloss_exceso",
  "delta_logloss"
))

lift <- rbindlist(lapply(modelos, function(cfg) {
  dt <- leer_dataset(file.path(cfg$path, "lift_validacion"))
  dt[, `:=`(modelo = cfg$modelo, variante = cfg$variante)]
  dt
}), fill = TRUE)

lift_base <- lift[variante == "base", .(
  modelo,
  top_pct,
  precision_base = precision,
  capture_rate_base = capture_rate,
  lift_base = lift
)]

lift_delta <- lift[
  variante == "base_exceso_levante",
  .(
    modelo,
    top_pct,
    precision_exceso = precision,
    capture_rate_exceso = capture_rate,
    lift_exceso = lift
  )
][
  lift_base,
  on = c("modelo", "top_pct")
]
lift_delta[, `:=`(
  delta_precision = precision_exceso - precision_base,
  delta_capture_rate = capture_rate_exceso - capture_rate_base,
  delta_lift = lift_exceso - lift_base
)]
setcolorder(lift_delta, c(
  "modelo",
  "top_pct",
  "precision_base",
  "precision_exceso",
  "delta_precision",
  "capture_rate_base",
  "capture_rate_exceso",
  "delta_capture_rate",
  "lift_base",
  "lift_exceso",
  "delta_lift"
))

importancia_xgb <- fread(file.path(out_dir, "xgboost_com_base_exceso_levante_features_importancia.csv"))
importancia_exceso_xgb <- importancia_xgb[grepl("^exceso_", feature)]

fwrite(metricas, file.path(out_dir, "comparacion_metricas_com_exceso_levante.csv"))
fwrite(metricas_delta, file.path(out_dir, "comparacion_metricas_com_exceso_levante_delta.csv"))
fwrite(lift, file.path(out_dir, "comparacion_lift_com_exceso_levante.csv"))
fwrite(lift_delta, file.path(out_dir, "comparacion_lift_com_exceso_levante_delta.csv"))
fwrite(importancia_exceso_xgb, file.path(out_dir, "importancia_exceso_levante_xgboost_com.csv"))

print(metricas_delta[order(modelo, split)])
print(lift_delta[order(modelo, top_pct)])
print(importancia_exceso_xgb)
