library(data.table)
library(arrow)

escenarios <- c(
  "operativo_minimo",
  "operativo_segmento",
  "operativo_clima",
  "segmento_clima",
  "amplio_actual"
)

base_outputs <- "zona_limpia/outputs/experimentos_cascada_zl"
base_modelos <- "data/processed/modelos/experimentos_cascada_zl"
out_dir <- base_outputs
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

leer_csv_feature_set <- function(feature_set, archivo) {
  path <- file.path(base_outputs, feature_set, archivo)
  if (!file.exists(path)) {
    warning("No existe archivo: ", path)
    return(data.table())
  }
  dt <- fread(path)
  dt[, feature_set_zl := feature_set]
  dt
}

leer_parquet_feature_set <- function(feature_set, subdir) {
  path <- file.path(base_modelos, feature_set, subdir)
  if (!dir.exists(path)) {
    warning("No existe dataset: ", path)
    return(data.table())
  }
  dt <- as.data.table(arrow::open_dataset(path, format = "parquet"))
  dt[, feature_set_zl := feature_set]
  dt
}

metricas <- rbindlist(lapply(
  escenarios,
  leer_csv_feature_set,
  archivo = "modelo_zl_observado_metricas.csv"
), fill = TRUE)

lift <- rbindlist(lapply(
  escenarios,
  leer_csv_feature_set,
  archivo = "modelo_zl_observado_lift.csv"
), fill = TRUE)

features <- rbindlist(lapply(
  escenarios,
  leer_csv_feature_set,
  archivo = "modelo_zl_observado_features_importancia.csv"
), fill = TRUE)

parametros <- rbindlist(lapply(
  escenarios,
  leer_parquet_feature_set,
  subdir = "parametros"
), fill = TRUE)

metricas_resumen <- metricas[
  split %in% c("validacion", "test"),
  .(
    feature_set_zl,
    escenario,
    split,
    n,
    positivos,
    prevalencia,
    auc,
    logloss
  )
][order(escenario, split, -auc)]

metricas_wide <- dcast(
  metricas_resumen,
  feature_set_zl + escenario ~ split,
  value.var = c("auc", "logloss")
)
metricas_wide[, delta_auc_test_validacion := auc_test - auc_validacion]

lift_resumen <- lift[
  split %in% c("validacion", "test"),
  .(
    feature_set_zl,
    escenario,
    split,
    top_pct,
    n,
    positivos,
    precision,
    capture_rate,
    lift
  )
][order(escenario, split, top_pct, -lift)]

features_top <- features[
  ,
  head(.SD[order(-Gain)], 20),
  by = .(feature_set_zl, escenario)
]

familias_top <- features[
  ,
  .(
    gain_total = sum(Gain, na.rm = TRUE),
    frecuencia_total = sum(Frequency, na.rm = TRUE),
    n_features = uniqueN(feature)
  ),
  by = .(feature_set_zl, escenario, familia)
][order(feature_set_zl, escenario, -gain_total)]

fwrite(metricas, file.path(out_dir, "cascada_zl_metricas.csv"))
fwrite(metricas_resumen, file.path(out_dir, "cascada_zl_metricas_resumen_valid_test.csv"))
fwrite(metricas_wide, file.path(out_dir, "cascada_zl_metricas_wide.csv"))
fwrite(lift, file.path(out_dir, "cascada_zl_lift.csv"))
fwrite(lift_resumen, file.path(out_dir, "cascada_zl_lift_resumen_valid_test.csv"))
fwrite(features, file.path(out_dir, "cascada_zl_features_importancia.csv"))
fwrite(features_top, file.path(out_dir, "cascada_zl_features_top20.csv"))
fwrite(familias_top, file.path(out_dir, "cascada_zl_importancia_por_familia.csv"))
fwrite(parametros, file.path(out_dir, "cascada_zl_parametros.csv"))

print(metricas_wide[order(escenario, -auc_validacion)])
print(lift_resumen[split == "validacion" & top_pct %in% c(0.05, 0.10)][order(escenario, top_pct, -lift)])
if (nrow(parametros) > 0L) {
  print(parametros[, .(
    features_numericas = max(features_numericas, na.rm = TRUE),
    features_categoricas = max(features_categoricas, na.rm = TRUE),
    features_clima = max(features_clima, na.rm = TRUE),
    columnas_matriz = max(columnas_matriz, na.rm = TRUE)
  ), by = .(feature_set_zl, escenario)])
}
