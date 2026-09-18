library(data.table)

path_out <- "outputs/reevaluacion_2026/validacion"

leer <- function(nombre) {
  path <- file.path(path_out, paste0(nombre, ".csv"))
  if (!file.exists(path)) stop("Falta salida: ", path)
  fread(path)
}

metricas_com <- leer("metricas_com")
metricas_com_mes <- leer("metricas_com_mes")
lift_diario_com <- leer("lift_diario_com")
metricas_agregados <- leer("metricas_agregados")
metricas_agregados_mes <- leer("metricas_agregados_mes")
metricas_zl <- leer("metricas_zl")
metricas_zl_mes <- leer("metricas_zl_mes")
lift_diario_zl <- leer("lift_diario_zl")

esperados_com <- c("com_logistico_reducido_d2", "com_xgboost_d2")
esperados_agregados <- c(
  "pronostico_a0",
  "pronostico_a0_xgb_compacto_q30",
  "inferencial_q30_ciclo"
)
esperados_zl <- c(
  "zl_operativo_segmento",
  "zl_operativo_segmento_demografia",
  "zl_amplio_actual"
)
meses_validacion <- 202604:202606

stopifnot(
  setequal(metricas_com$candidato, esperados_com),
  setequal(metricas_agregados$candidato, esperados_agregados),
  setequal(metricas_zl$candidato, esperados_zl),
  setequal(metricas_com_mes$anio_mes, meses_validacion),
  setequal(metricas_agregados_mes$anio_mes, meses_validacion),
  setequal(metricas_zl_mes$anio_mes, meses_validacion),
  all(metricas_agregados$dias == 91L),
  all(lift_diario_com$dias == 91L),
  all(lift_diario_zl$dias == 87L)
)

columnas_finitas <- list(
  com = metricas_com[, .(auc, logloss, brier)],
  agregados = metricas_agregados[, .(mae, rmse, correlacion, r2)],
  zl = metricas_zl[, .(auc, logloss, brier)]
)
stopifnot(all(vapply(columnas_finitas, function(x) all(is.finite(as.matrix(x))), logical(1))))

com_ref <- metricas_com[candidato == "com_logistico_reducido_d2"]
com_xgb <- metricas_com[candidato == "com_xgboost_d2"]
stopifnot(
  com_xgb$auc > com_ref$auc,
  com_xgb$logloss < com_ref$logloss,
  com_xgb$brier < com_ref$brier
)

a0 <- metricas_agregados[candidato == "pronostico_a0"]
a0_xgb <- metricas_agregados[candidato == "pronostico_a0_xgb_compacto_q30"]
stopifnot(
  a0_xgb$rmse < a0$rmse,
  a0_xgb$mae < a0$mae,
  a0_xgb$correlacion > a0$correlacion
)

zl_ref <- metricas_zl[candidato == "zl_operativo_segmento"]
zl_demografia <- metricas_zl[candidato == "zl_operativo_segmento_demografia"]
zl_amplio <- metricas_zl[candidato == "zl_amplio_actual"]
stopifnot(
  zl_demografia$auc > zl_ref$auc,
  zl_demografia$logloss < zl_ref$logloss,
  zl_demografia$brier < zl_ref$brier,
  zl_amplio$auc > zl_ref$auc,
  zl_amplio$logloss < zl_ref$logloss,
  zl_amplio$brier < zl_ref$brier
)

stopifnot(
  metricas_com_mes[
    , all(auc[candidato == "com_xgboost_d2"] > auc[candidato == "com_logistico_reducido_d2"]),
    by = anio_mes
  ][, all(V1)],
  metricas_agregados_mes[
    , all(rmse[candidato == "pronostico_a0_xgb_compacto_q30"] < rmse[candidato == "pronostico_a0"]),
    by = anio_mes
  ][, all(V1)],
  metricas_zl_mes[
    , all(auc[candidato == "zl_operativo_segmento_demografia"] > auc[candidato == "zl_operativo_segmento"]),
    by = anio_mes
  ][, all(V1)],
  metricas_zl_mes[
    , all(auc[candidato == "zl_amplio_actual"] > auc[candidato == "zl_operativo_segmento"]),
    by = anio_mes
  ][, all(V1)]
)

archivos <- list.files(path_out, recursive = TRUE, full.names = TRUE)
stopifnot(
  !any(grepl("bootstrap", archivos, ignore.case = TRUE)),
  !any(grepl("test", archivos, ignore.case = TRUE))
)

cat("VALIDACION_COMPARACION_OK\n")
