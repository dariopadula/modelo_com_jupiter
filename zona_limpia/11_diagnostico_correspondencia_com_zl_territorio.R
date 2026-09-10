library(arrow)
library(data.table)

path_comparacion_zl <- "data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia"
path_cluster_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
out_outputs <- "zona_limpia/outputs"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
meses_analisis <- as.integer(strsplit(
  Sys.getenv("MESES_ANALISIS_CORRESPONDENCIA_ZL", unset = "202510,202511,202512,202603,202604,202605"),
  ","
)[[1]])
municipios_excluir <- strsplit(
  Sys.getenv("MUNICIPIOS_EXCLUIR_CORRESPONDENCIA_ZL", unset = "B"),
  ","
)[[1]]

dir.create(out_outputs, recursive = TRUE, showWarnings = FALSE)

dividir_seguro <- function(numerador, denominador) {
  data.table::fifelse(denominador > 0, numerador / denominador, NA_real_)
}

comparacion_zl <- as.data.table(arrow::open_dataset(path_comparacion_zl, format = "parquet"))
cluster_admin <- as.data.table(arrow::open_dataset(path_cluster_admin, format = "parquet"))

if (is.na(target_version_cluster) || target_version_cluster == "") {
  versiones <- sort(unique(comparacion_zl$version_cluster))
  target_version_cluster <- versiones[length(versiones)]
}

comparacion_zl[, version_cluster := as.character(version_cluster)]
comparacion_zl[, cluster_id := as.character(cluster_id)]
cluster_admin[, version_cluster := as.character(version_cluster)]
cluster_admin[, cluster_id := as.character(cluster_id)]

comparacion_zl <- comparacion_zl[
  version_cluster == target_version_cluster &
    anio_mes %in% meses_analisis
]
cluster_admin <- cluster_admin[
  version_cluster == target_version_cluster,
  .(cluster_id, municipio, ccz, nombre_barrio_ine)
]

datos <- cluster_admin[
  comparacion_zl,
  on = "cluster_id"
]

datos[, municipio := toupper(trimws(as.character(municipio)))]
datos[, ccz := as.character(ccz)]
datos <- datos[
  !municipio %in% municipios_excluir &
    hay_zl_visita_efectiva == TRUE &
    hay_zl_voluminosos != TRUE
]

datos[, `:=`(
  problema_zl = hay_zl_problema_comparable == TRUE,
  reclamo_com = hay_com == TRUE,
  limpio_zl = hay_zl_limpio == TRUE
)]

resumir_correspondencia <- function(dt, by_cols) {
  dt[
    ,
    .(
      cluster_dia_observados = .N,
      clusters_observados = uniqueN(cluster_id),
      visitas_efectivas = sum(hay_zl_visita_efectiva),
      zl_problema = sum(problema_zl),
      com = sum(reclamo_com),
      ambos = sum(problema_zl & reclamo_com),
      solo_zl_problema = sum(problema_zl & !reclamo_com),
      solo_com_zl_limpio = sum(reclamo_com & limpio_zl & !problema_zl),
      ambos_sin_problema = sum(!problema_zl & !reclamo_com & limpio_zl),
      zl_limpio = sum(limpio_zl)
    ),
    by = by_cols
  ][
    ,
    `:=`(
      tasa_com_dado_zl_problema = dividir_seguro(ambos, zl_problema),
      tasa_no_com_dado_zl_problema = dividir_seguro(solo_zl_problema, zl_problema),
      tasa_zl_problema_dado_com = dividir_seguro(ambos, com),
      tasa_com_con_zl_limpio = dividir_seguro(solo_com_zl_limpio, com),
      tasa_zl_problema_en_observados = dividir_seguro(zl_problema, cluster_dia_observados),
      tasa_com_en_observados = dividir_seguro(com, cluster_dia_observados),
      ratio_zl_problema_com = dividir_seguro(zl_problema, com)
    )
  ][]
}

resumen_municipio <- resumir_correspondencia(datos, "municipio")[
  order(tasa_com_dado_zl_problema)
]

resumen_ccz <- resumir_correspondencia(datos, c("municipio", "ccz"))[
  order(tasa_com_dado_zl_problema)
]

resumen_barrio <- resumir_correspondencia(datos, c("municipio", "ccz", "nombre_barrio_ine"))[
  cluster_dia_observados >= 100
][
  order(tasa_com_dado_zl_problema)
]

resumen_mensual_municipio <- resumir_correspondencia(datos, c("anio_mes", "municipio"))[
  order(anio_mes, municipio)
]

resumen_global <- resumir_correspondencia(datos, character())
resumen_global[, `:=`(
  version_cluster = target_version_cluster,
  meses_analisis = paste(meses_analisis, collapse = ","),
  municipios_excluidos = paste(municipios_excluir, collapse = ",")
)]

data.table::fwrite(
  resumen_global,
  file.path(out_outputs, "correspondencia_com_zl_territorio_global.csv")
)
data.table::fwrite(
  resumen_municipio,
  file.path(out_outputs, "correspondencia_com_zl_territorio_municipio.csv")
)
data.table::fwrite(
  resumen_ccz,
  file.path(out_outputs, "correspondencia_com_zl_territorio_ccz.csv")
)
data.table::fwrite(
  resumen_barrio,
  file.path(out_outputs, "correspondencia_com_zl_territorio_barrio.csv")
)
data.table::fwrite(
  resumen_mensual_municipio,
  file.path(out_outputs, "correspondencia_com_zl_territorio_mensual_municipio.csv")
)

print(resumen_global)
print(resumen_municipio)
print(resumen_ccz[order(tasa_com_dado_zl_problema)][1:10])
print(resumen_ccz[order(-tasa_com_dado_zl_problema)][1:10])
