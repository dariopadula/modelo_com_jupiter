library(arrow)
library(data.table)

path_com <- "data/processed/modelos/reevaluacion_2026/com_cluster"
path_agregados <- "data/processed/modelos/reevaluacion_2026/agregados_inferencia"
path_zl <- "data/processed/modelos/reevaluacion_2026/zona_limpia"
path_out <- "outputs/reevaluacion_2026"
dir.create(path_out, recursive = TRUE, showWarnings = FALSE)

inventario <- rbindlist(list(
  fread(file.path(path_com, "inventario.csv")),
  fread(file.path(path_agregados, "inventario.csv")),
  fread(file.path(path_zl, "inventario.csv"))
), fill = TRUE)

candidatos_esperados <- c(
  "com_logistico_reducido_d2",
  "com_xgboost_d2",
  "pronostico_a0",
  "pronostico_a0_xgb_compacto_q30",
  "inferencial_q30_ciclo",
  "zl_operativo_segmento",
  "zl_operativo_segmento_demografia",
  "zl_amplio_actual"
)
if (!setequal(inventario$candidato, candidatos_esperados) ||
    anyDuplicated(inventario$candidato)) {
  stop("El inventario de candidatos no coincide con el definido")
}
if (inventario[version_split != "reevaluacion_2026_v1" | usa_test | bootstrap, .N]) {
  stop("Hay candidatos fuera del split, usando test o con bootstrap")
}

pred_com <- as.data.table(arrow::read_parquet(
  file.path(path_com, "predicciones_validacion.parquet")
))
pred_agregados <- fread(file.path(path_agregados, "predicciones_diarias_validacion.csv"))
pred_zl <- as.data.table(arrow::read_parquet(
  file.path(path_zl, "predicciones_validacion.parquet")
))
for (dt in list(pred_com, pred_agregados, pred_zl)) dt[, dia := as.IDate(dia)]

validar_predicciones <- function(dt, candidatos, score_col) {
  if (!setequal(unique(dt$candidato), candidatos)) {
    stop("Faltan candidatos en predicciones")
  }
  if (dt[split != "validacion" | dia < as.IDate("2026-04-01") |
         dia > as.IDate("2026-06-30"), .N]) {
    stop("Hay predicciones fuera de validacion")
  }
  if (dt[, any(!is.finite(get(score_col)))]) stop("Hay predicciones no finitas")
}

validar_predicciones(
  pred_com,
  c("com_logistico_reducido_d2", "com_xgboost_d2"),
  "pred_prob"
)
if (pred_com[, any(pred_prob < 0 | pred_prob > 1)]) {
  stop("Hay probabilidades COM fuera de [0, 1]")
}
validar_predicciones(
  pred_agregados,
  c("pronostico_a0", "pronostico_a0_xgb_compacto_q30", "inferencial_q30_ciclo"),
  "predicho"
)
if (pred_agregados[, any(predicho < 0)]) stop("Hay conteos predichos negativos")
validar_predicciones(
  pred_zl,
  c(
    "zl_operativo_segmento",
    "zl_operativo_segmento_demografia",
    "zl_amplio_actual"
  ),
  "pred_prob"
)
if (pred_zl[, any(pred_prob < 0 | pred_prob > 1)]) {
  stop("Hay probabilidades ZL fuera de [0, 1]")
}

modelo_logistico <- readRDS(file.path(path_com, "com_logistico_reducido_d2.rds"))
modelo_a0 <- readRDS(file.path(path_agregados, "pronostico_a0.rds"))
modelo_inferencial <- readRDS(file.path(path_agregados, "inferencial_q30_ciclo.rds"))
if (!isTRUE(modelo_logistico$fit$converged)) stop("El logistico COM no convergio")
if (!isTRUE(modelo_a0$fit$converged)) stop("A0 no convergio")
if (!isTRUE(modelo_inferencial$fit$converged)) stop("El inferencial no convergio")

archivos_nuevos <- list.files(
  "data/processed/modelos/reevaluacion_2026",
  recursive = TRUE, full.names = TRUE
)
if (any(grepl("test|metric", basename(archivos_nuevos), ignore.case = TRUE))) {
  stop("Se generaron artefactos de test o metricas antes del paso 6")
}

fwrite(inventario[order(familia, candidato)], file.path(path_out, "inventario_candidatos.csv"))
controles <- data.table(
  control = c(
    "inventario_completo", "split_congelado", "sin_test",
    "sin_bootstrap", "predicciones_validacion", "rangos_prediccion",
    "convergencia_bam_glm", "artefactos_modelo_sin_metricas"
  ),
  estado = "OK"
)
print(controles)
print(inventario[order(familia, candidato)])
