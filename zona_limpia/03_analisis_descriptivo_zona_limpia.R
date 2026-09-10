library(data.table)
library(arrow)

source("zona_limpia/funciones_zona_limpia.R")

path_com_completo <- "data/parquet/com_completo"
out_dir <- "zona_limpia/outputs"

if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

dividir_seguro <- function(numerador, denominador) {
  data.table::fifelse(denominador > 0, numerador / denominador, NA_real_)
}

datos <- as.data.table(arrow::open_dataset(path_com_completo, format = "parquet"))

zl <- datos[es_zona_limpia == TRUE]
zl <- filtrar_periodo_analisis_zona_limpia(zl)

if (!"incidente_zona_limpia_mapeado" %in% names(zl)) {
  stop("La base com_completo no tiene incidente_zona_limpia_mapeado. Regenerar con 01_generar_com_completo.R.")
}

categorias_problema <- c(
  "Zona limpia - Basura fuera",
  "Zona limpia - Contenedor desbordado",
  "Zona limpia - Voluminosos"
)
categorias_limpio <- "Zona limpia - Limpio - No intervenido"
categorias_no_encontrado <- "Zona limpia - No se encuentra"
categorias_no_visitado <- "Zona limpia - No visitado"
categorias_no_realizado <- "Zona limpia - No se pudo realizar"

zl[, es_hallazgo_problema := incidente_zona_limpia_mapeado %in% categorias_problema]
zl[, es_limpio := incidente_zona_limpia_mapeado %in% categorias_limpio]
zl[, es_no_encontrado := incidente_zona_limpia_mapeado %in% categorias_no_encontrado]
zl[, es_no_visitado := incidente_zona_limpia_mapeado %in% categorias_no_visitado]
zl[, es_no_realizado := incidente_zona_limpia_mapeado %in% categorias_no_realizado]
zl[, es_visita_efectiva := es_hallazgo_problema | es_limpio]

resumen_total_categoria <- zl[
  ,
  .N,
  by = .(incidente_zona_limpia_mapeado, tipo_zona_limpia)
][
  order(-N)
]
resumen_total_categoria[, pct_total := N / sum(N)]

resumen_mensual_categoria <- zl[
  ,
  .N,
  by = .(anio_mes, incidente_zona_limpia_mapeado, tipo_zona_limpia)
][
  order(anio_mes, -N)
]
resumen_mensual_categoria[
  ,
  pct_mes := N / sum(N),
  by = anio_mes
]

metricas_total <- zl[
  ,
  .(
    n_total_zona_limpia = .N,
    n_visitas_efectivas = sum(es_visita_efectiva),
    n_hallazgos_problema = sum(es_hallazgo_problema),
    n_limpio = sum(es_limpio),
    n_no_visitado = sum(es_no_visitado),
    n_no_encontrado = sum(es_no_encontrado),
    n_no_realizado = sum(es_no_realizado)
  )
]
metricas_total[, tasa_hallazgo_sobre_visitas_efectivas := dividir_seguro(n_hallazgos_problema, n_visitas_efectivas)]
metricas_total[, tasa_limpio_sobre_visitas_efectivas := dividir_seguro(n_limpio, n_visitas_efectivas)]
metricas_total[, tasa_no_visitado_sobre_total := dividir_seguro(n_no_visitado, n_total_zona_limpia)]
metricas_total[, tasa_no_encontrado_sobre_total := dividir_seguro(n_no_encontrado, n_total_zona_limpia)]
metricas_total[, tasa_no_realizado_sobre_total := dividir_seguro(n_no_realizado, n_total_zona_limpia)]

metricas_mensuales <- zl[
  ,
  .(
    n_total_zona_limpia = .N,
    n_visitas_efectivas = sum(es_visita_efectiva),
    n_hallazgos_problema = sum(es_hallazgo_problema),
    n_limpio = sum(es_limpio),
    n_no_visitado = sum(es_no_visitado),
    n_no_encontrado = sum(es_no_encontrado),
    n_no_realizado = sum(es_no_realizado)
  ),
  by = anio_mes
][
  order(anio_mes)
]
metricas_mensuales[, tasa_hallazgo_sobre_visitas_efectivas := dividir_seguro(n_hallazgos_problema, n_visitas_efectivas)]
metricas_mensuales[, tasa_limpio_sobre_visitas_efectivas := dividir_seguro(n_limpio, n_visitas_efectivas)]
metricas_mensuales[, tasa_no_visitado_sobre_total := dividir_seguro(n_no_visitado, n_total_zona_limpia)]
metricas_mensuales[, tasa_no_encontrado_sobre_total := dividir_seguro(n_no_encontrado, n_total_zona_limpia)]
metricas_mensuales[, tasa_no_realizado_sobre_total := dividir_seguro(n_no_realizado, n_total_zona_limpia)]

data.table::fwrite(
  resumen_total_categoria,
  file.path(out_dir, "analisis_descriptivo_resumen_total_categoria.csv")
)
data.table::fwrite(
  resumen_mensual_categoria,
  file.path(out_dir, "analisis_descriptivo_resumen_mensual_categoria.csv")
)
data.table::fwrite(
  metricas_total,
  file.path(out_dir, "analisis_descriptivo_metricas_total.csv")
)
data.table::fwrite(
  metricas_mensuales,
  file.path(out_dir, "analisis_descriptivo_metricas_mensuales.csv")
)

print(resumen_total_categoria)
print(metricas_total)
print(metricas_mensuales)
