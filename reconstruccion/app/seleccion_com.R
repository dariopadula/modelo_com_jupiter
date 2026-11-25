# Seleccion de producto preparado, sin inferencia.

# Selecciona clusters por umbral, cantidad o porcentaje del bloque.  Entradas:
# producto, estrategia y valor. Salida: filas seleccionadas en orden de riesgo.
rf_select_com <- function(data, strategy = "umbral", value = 0.5) {
  if (length(value) != 1L || !is.finite(value) || value < 0)
    stop("Valor de seleccion invalido")
  data <- data[order(-data$pred_prob, data$ranking_dia), , drop = FALSE]
  if (strategy == "umbral") {
    if (value > 1)
      stop("Umbral fuera de rango")
    return(data[data$pred_prob >= value, , drop = FALSE])
  }
  if (strategy == "porcentaje_global") {
    if (value > 100)
      stop("Porcentaje fuera de rango")
    n <- ceiling(nrow(data) * value/100)
  } else if (strategy == "fijo_global")
    n <- round(value) else stop("Estrategia no disponible en R03")
  head(data, max(0L, min(as.integer(n), nrow(data))))
}
