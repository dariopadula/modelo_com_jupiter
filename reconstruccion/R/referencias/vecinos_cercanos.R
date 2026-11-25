# Busca vecinos espaciales usando FNN o nabor sin cambiar la referencia.  Entradas y
# parametros: ver firma; tablas en memoria y referencia explicita.  Salida: tabla o
# lista de derivados; no escribe archivos ni consulta servicios.  Procedencia:
# funciones/vecinos_cercanos.R; migracion R04.

vecinos_cercanos <- function(data, query, k = 1L) {
  data <- as.matrix(data)
  query <- as.matrix(query)

  if (!is.numeric(data) || !is.numeric(query)) {
    stop("data y query deben ser matrices numericas")
  }
  if (ncol(data) != ncol(query)) {
    stop("data y query deben tener la misma cantidad de columnas")
  }

  if (requireNamespace("FNN", quietly = TRUE)) {
    return(FNN::get.knnx(data = data, query = query, k = k))
  }
  if (requireNamespace("nabor", quietly = TRUE)) {
    nn <- nabor::knn(data = data, query = query, k = k)
    return(list(nn.index = nn$nn.idx, nn.dist = nn$nn.dists))
  }

  stop("Se necesita FNN o nabor para calcular vecinos cercanos")
}
