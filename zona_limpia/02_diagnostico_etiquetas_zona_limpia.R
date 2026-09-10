library(data.table)
library(arrow)

path_com_completo <- "data/parquet/com_completo"
out_dir <- "zona_limpia/outputs"

if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

datos <- as.data.table(arrow::open_dataset(path_com_completo, format = "parquet"))

resumen_incidentes <- datos[
  ,
  .N,
  by = .(es_incidente_modelo, es_zona_limpia, incidente_normalizado)
][order(-N)]

etiquetas_zona_limpia <- datos[
  es_zona_limpia == TRUE,
  .N,
  by = .(
    incidente_original,
    incidente_zona_limpia_normalizado,
    incidente_zona_limpia_mapeado,
    tipo_zona_limpia
  )
][order(-N)]

resumen_mapeado_zona_limpia <- datos[
  es_zona_limpia == TRUE,
  .N,
  by = .(incidente_zona_limpia_mapeado, tipo_zona_limpia)
][order(-N)]

resumen_mensual_zona_limpia <- datos[
  es_zona_limpia == TRUE,
  .N,
  by = .(anio_mes, incidente_zona_limpia_mapeado, tipo_zona_limpia)
][order(anio_mes, incidente_zona_limpia_mapeado)]

data.table::fwrite(
  resumen_incidentes,
  file.path(out_dir, "resumen_incidentes_com_completo.csv")
)
data.table::fwrite(
  etiquetas_zona_limpia,
  file.path(out_dir, "etiquetas_zona_limpia.csv")
)
data.table::fwrite(
  resumen_mapeado_zona_limpia,
  file.path(out_dir, "resumen_mapeado_zona_limpia.csv")
)
data.table::fwrite(
  resumen_mensual_zona_limpia,
  file.path(out_dir, "resumen_mensual_zona_limpia.csv")
)

print(resumen_incidentes)
print(etiquetas_zona_limpia)
print(resumen_mapeado_zona_limpia)
