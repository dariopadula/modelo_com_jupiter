library(data.table)

path_out <- "outputs/reevaluacion_2026/exploracion_inferencia_q7_sola"
metricas <- fread(file.path(path_out, "metricas_validacion.csv"))
metricas_mes <- fread(file.path(path_out, "metricas_validacion_mes.csv"))
predicciones <- fread(file.path(path_out, "predicciones_validacion.csv"))
modelo <- readRDS(file.path(path_out, "inferencial_q7_sola.rds"))

esperados <- c("inferencial_q30_ciclo", "inferencial_q7_sola")
stopifnot(
  setequal(metricas$candidato, esperados),
  setequal(metricas_mes$candidato, esperados),
  setequal(metricas_mes$anio_mes, 202604:202606),
  setequal(predicciones$candidato, esperados),
  all(as.IDate(predicciones$dia) >= as.IDate("2026-04-01")),
  all(as.IDate(predicciones$dia) <= as.IDate("2026-06-30")),
  all(metricas$dias == 91L),
  isTRUE(modelo$fit$converged),
  identical(modelo$version_split, "reevaluacion_2026_v1"),
  identical(modelo$usa_test, FALSE),
  identical(modelo$bootstrap, FALSE)
)

actual <- metricas[candidato == "inferencial_q30_ciclo"]
q7 <- metricas[candidato == "inferencial_q7_sola"]
stopifnot(
  q7$rmse > actual$rmse,
  q7$mae > actual$mae,
  abs(q7$sesgo) > abs(actual$sesgo),
  q7$correlacion > actual$correlacion
)

cat("VALIDACION_EXPLORACION_Q7_SOLA_OK\n")
