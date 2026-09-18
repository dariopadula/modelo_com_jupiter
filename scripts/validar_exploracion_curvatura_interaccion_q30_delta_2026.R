library(data.table)

path_out <- paste0(
  "outputs/reevaluacion_2026/",
  "exploracion_inferencia_curvatura_interaccion_q30_delta"
)
archivos <- c(
  "modelos_exploratorios.rds", "predicciones_validacion.csv",
  "metricas_validacion.csv", "metricas_validacion_mes.csv",
  "coeficientes.csv", "ajuste_train.csv", "preparacion_variables.csv",
  "comparacion_predicciones.csv"
)
faltantes <- archivos[!file.exists(file.path(path_out, archivos))]
if (length(faltantes)) stop("Faltan salidas: ", paste(faltantes, collapse = ", "))

objeto <- readRDS(file.path(path_out, "modelos_exploratorios.rds"))
if (!identical(objeto$version_split, "reevaluacion_2026_v1")) {
  stop("Version de split inesperada")
}
if (!identical(objeto$usa_test, FALSE)) stop("La exploracion declara uso de test")
if (!identical(objeto$bootstrap, FALSE)) stop("La exploracion declara bootstrap")
if (!all(vapply(objeto$fits, function(x) isTRUE(x$converged), logical(1)))) {
  stop("Hay modelos sin convergencia")
}

esperados <- c(
  "inferencial_q30_ciclo", "inferencial_delta_cuadratico",
  "inferencial_delta_cuadratico_sin_h_delta",
  "inferencial_q30_por_delta"
)
metricas <- fread(file.path(path_out, "metricas_validacion.csv"))
if (!setequal(metricas$candidato, esperados)) stop("Candidatos inesperados")
if (any(metricas$dias != 91L)) stop("La validacion no contiene 91 dias")
columnas_numericas <- c("sesgo", "mae", "rmse", "correlacion", "r2")
if (any(!is.finite(as.matrix(metricas[, ..columnas_numericas])))) {
  stop("Hay metricas no finitas")
}

pred <- fread(file.path(path_out, "predicciones_validacion.csv"))
if (any(as.IDate(pred$dia) > as.IDate("2026-06-30"))) {
  stop("Las predicciones incluyen fechas posteriores a validacion")
}
if (pred[, uniqueN(dia), by = candidato][, any(V1 != 91L)]) {
  stop("Cantidad inesperada de dias por candidato")
}
if (pred[, any(predicho < 0 | predicho > n_clusters_total)]) {
  stop("Hay pronosticos fuera del rango posible")
}

coef <- fread(file.path(path_out, "coeficientes.csv"))
if (!coef[candidato == "inferencial_delta_cuadratico",
          any(termino == "z_delta_q_7_30_sq")]) {
  stop("Falta el termino cuadratico")
}
if (!coef[candidato == "inferencial_delta_cuadratico_sin_h_delta",
          any(termino == "z_delta_q_7_30_sq")]) {
  stop("Falta el termino cuadratico en la variante simplificada")
}
if (coef[candidato == "inferencial_delta_cuadratico_sin_h_delta",
         any(termino == "z_media_h:z_delta_q_7_30")]) {
  stop("La variante simplificada conserva la interaccion h por cambio")
}
if (!coef[candidato == "inferencial_q30_por_delta",
          any(termino == "z_media_q_30:z_delta_q_7_30")]) {
  stop("Falta la interaccion q30 por cambio")
}

comparacion <- fread(file.path(path_out, "comparacion_predicciones.csv"))
if (!is.finite(comparacion$correlacion_predicciones) ||
    comparacion$correlacion_predicciones < 0.99) {
  stop("Las variantes no tienen la similitud esperada")
}

cat("VALIDACION_CURVATURA_INTERACCION_Q30_DELTA_OK\n")
