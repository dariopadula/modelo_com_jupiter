# Lector de producto preparado. No importa adaptadores ni calcula predicciones.

# Lee el producto COM generado fuera de Shiny.  Entrada: raiz propia. Salida: tabla
# ordenada con coordenadas validas.
rf_read_com_product <- function(root) {
  path <- file.path(root, "runtime/r03_com/producto_com_actual.rds")
  if (!file.exists(path))
    stop("Falta producto COM R03 preparado")
  data <- readRDS(path)
  if (!is.data.frame(data) || !nrow(data) || anyNA(data[c("lng", "lat")]))
    stop("Producto COM invalido")
  data[order(data$ranking_dia), ]
}
