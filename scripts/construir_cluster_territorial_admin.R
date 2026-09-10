library(arrow)
library(data.table)
library(sf)

path_cluster_actual <- "data/processed/cluster_update_check/contenedor_posicion_cluster_actual"
path_municipios <- "shp/sig_municipios/sig_municipios.shp"
path_ccz <- "shp/ccz_mvd_23_pg.gpkg"
path_barrios <- "shp/barrios_mvd_23_pg.gpkg"
out_base <- "data/processed/cluster_territorial"
out_outputs <- "data/processed/cluster_territorial/resumen"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
estados_cluster_validos <- c("referencia", "asignado", "revision")
crs_objetivo <- 32721

dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
dir.create(out_outputs, recursive = TRUE, showWarnings = FALSE)

paths_req <- c(path_municipios, path_ccz, path_barrios)
faltantes_paths <- paths_req[!file.exists(paths_req)]
if (length(faltantes_paths) > 0L) {
  stop("Faltan capas territoriales: ", paste(faltantes_paths, collapse = ", "))
}

dividir_seguro <- function(numerador, denominador) {
  data.table::fifelse(denominador > 0, numerador / denominador, NA_real_)
}

normalizar_nombre <- function(x) {
  x <- toupper(trimws(as.character(x)))
  iconv(x, from = "", to = "ASCII//TRANSLIT")
}

leer_capa <- function(path) {
  capa <- sf::st_read(path, quiet = TRUE)
  if (is.na(sf::st_crs(capa))) {
    stop("La capa no tiene CRS definido: ", path)
  }
  sf::st_transform(capa, crs_objetivo)
}

municipios <- leer_capa(path_municipios)
ccz <- leer_capa(path_ccz)
barrios <- leer_capa(path_barrios)

municipios_join <- municipios[, c("MUNICIPIO", "AREA_HA")]
data.table::setnames(
  municipios_join,
  old = c("MUNICIPIO", "AREA_HA"),
  new = c("municipio", "area_municipio_ha")
)

ccz_join <- ccz[, c(
  "CCZ",
  "NOMMUNICIPIO",
  "VIV_TOT_23",
  "POB_TOT_23",
  "POB_TOT_HOM_23",
  "POB_TOT_MUJ_23",
  "AREA_KM2",
  "AREA_HA"
)]
data.table::setnames(
  ccz_join,
  old = c(
    "CCZ",
    "NOMMUNICIPIO",
    "VIV_TOT_23",
    "POB_TOT_23",
    "POB_TOT_HOM_23",
    "POB_TOT_MUJ_23",
    "AREA_KM2",
    "AREA_HA"
  ),
  new = c(
    "ccz",
    "municipio_ccz",
    "viviendas_ccz_2023",
    "poblacion_ccz_2023",
    "poblacion_hombres_ccz_2023",
    "poblacion_mujeres_ccz_2023",
    "area_ccz_km2",
    "area_ccz_ha"
  )
)

barrios_join <- barrios[, c(
  "CODBARRIOINE",
  "NOMBARRIOINE",
  "VIV_TOT_23",
  "POB_TOT_23",
  "POB_TOT_HOM_23",
  "POB_TOT_MUJ_23",
  "AREA_KM2",
  "AREA_HA"
)]
data.table::setnames(
  barrios_join,
  old = c(
    "CODBARRIOINE",
    "NOMBARRIOINE",
    "VIV_TOT_23",
    "POB_TOT_23",
    "POB_TOT_HOM_23",
    "POB_TOT_MUJ_23",
    "AREA_KM2",
    "AREA_HA"
  ),
  new = c(
    "cod_barrio_ine",
    "nombre_barrio_ine",
    "viviendas_barrio_2023",
    "poblacion_barrio_2023",
    "poblacion_hombres_barrio_2023",
    "poblacion_mujeres_barrio_2023",
    "area_barrio_km2",
    "area_barrio_ha"
  )
)

contenedor_posicion_cluster <- as.data.table(
  arrow::open_dataset(path_cluster_actual, format = "parquet")
)

if (!is.na(target_version_cluster) && target_version_cluster != "") {
  contenedor_posicion_cluster <- contenedor_posicion_cluster[
    version_cluster == target_version_cluster
  ]
} else {
  versiones <- sort(unique(contenedor_posicion_cluster$version_cluster))
  target_version_cluster <- versiones[length(versiones)]
  contenedor_posicion_cluster <- contenedor_posicion_cluster[
    version_cluster == target_version_cluster
  ]
}

posiciones_cluster <- data.table::copy(contenedor_posicion_cluster[
  !is.na(cluster_id) &
    !is.na(x) & !is.na(y) &
    estado_asignacion_cluster %in% estados_cluster_validos
])

if (nrow(posiciones_cluster) == 0L) {
  stop("No hay posiciones validas para version_cluster = ", target_version_cluster)
}

cluster_centroide <- posiciones_cluster[
  ,
  .(
    x_cluster = mean(as.numeric(x), na.rm = TRUE),
    y_cluster = mean(as.numeric(y), na.rm = TRUE),
    n_posiciones_cluster = .N
  ),
  by = cluster_id
]

cluster_sf <- sf::st_as_sf(
  cluster_centroide,
  coords = c("x_cluster", "y_cluster"),
  crs = crs_objetivo,
  remove = FALSE
)

join_municipios <- sf::st_join(cluster_sf, municipios_join, join = sf::st_within, left = TRUE)
join_ccz <- sf::st_join(cluster_sf, ccz_join, join = sf::st_within, left = TRUE)
join_barrios <- sf::st_join(cluster_sf, barrios_join, join = sf::st_within, left = TRUE)

dt_municipios <- as.data.table(sf::st_drop_geometry(join_municipios))
dt_ccz <- as.data.table(sf::st_drop_geometry(join_ccz))
dt_barrios <- as.data.table(sf::st_drop_geometry(join_barrios))

cluster_admin <- dt_municipios[
  ,
  .(
    cluster_id,
    x_cluster,
    y_cluster,
    n_posiciones_cluster,
    municipio,
    area_municipio_ha
  )
][
  dt_ccz[
    ,
    .(
      cluster_id,
      ccz,
      municipio_ccz,
      viviendas_ccz_2023,
      poblacion_ccz_2023,
      poblacion_hombres_ccz_2023,
      poblacion_mujeres_ccz_2023,
      area_ccz_km2,
      area_ccz_ha
    )
  ],
  on = "cluster_id"
][
  dt_barrios[
    ,
    .(
      cluster_id,
      cod_barrio_ine,
      nombre_barrio_ine,
      viviendas_barrio_2023,
      poblacion_barrio_2023,
      poblacion_hombres_barrio_2023,
      poblacion_mujeres_barrio_2023,
      area_barrio_km2,
      area_barrio_ha
    )
  ],
  on = "cluster_id"
]

cluster_admin[, `:=`(
  municipio = normalizar_nombre(municipio),
  municipio_ccz = normalizar_nombre(municipio_ccz),
  nombre_barrio_ine = normalizar_nombre(nombre_barrio_ine),
  densidad_pob_ccz_2023_km2 = dividir_seguro(poblacion_ccz_2023, area_ccz_km2),
  densidad_viv_ccz_2023_km2 = dividir_seguro(viviendas_ccz_2023, area_ccz_km2),
  densidad_pob_barrio_2023_km2 = dividir_seguro(poblacion_barrio_2023, area_barrio_km2),
  densidad_viv_barrio_2023_km2 = dividir_seguro(viviendas_barrio_2023, area_barrio_km2),
  version_cluster = target_version_cluster
)]

cols_orden <- c(
  "version_cluster",
  "cluster_id",
  "x_cluster",
  "y_cluster",
  "n_posiciones_cluster",
  "municipio",
  "area_municipio_ha",
  "ccz",
  "municipio_ccz",
  "poblacion_ccz_2023",
  "viviendas_ccz_2023",
  "poblacion_hombres_ccz_2023",
  "poblacion_mujeres_ccz_2023",
  "area_ccz_km2",
  "area_ccz_ha",
  "densidad_pob_ccz_2023_km2",
  "densidad_viv_ccz_2023_km2",
  "cod_barrio_ine",
  "nombre_barrio_ine",
  "poblacion_barrio_2023",
  "viviendas_barrio_2023",
  "poblacion_hombres_barrio_2023",
  "poblacion_mujeres_barrio_2023",
  "area_barrio_km2",
  "area_barrio_ha",
  "densidad_pob_barrio_2023_km2",
  "densidad_viv_barrio_2023_km2"
)
cluster_admin <- cluster_admin[, ..cols_orden]

resumen <- cluster_admin[
  ,
  .(
    clusters = .N,
    clusters_sin_municipio = sum(is.na(municipio)),
    clusters_sin_ccz = sum(is.na(ccz)),
    clusters_sin_barrio = sum(is.na(cod_barrio_ine)),
    municipios = uniqueN(municipio, na.rm = TRUE),
    ccz = uniqueN(ccz, na.rm = TRUE),
    barrios = uniqueN(cod_barrio_ine, na.rm = TRUE)
  ),
  by = version_cluster
]

resumen_municipio <- cluster_admin[
  ,
  .(
    clusters = .N,
    ccz = uniqueN(ccz, na.rm = TRUE),
    barrios = uniqueN(cod_barrio_ine, na.rm = TRUE)
  ),
  by = .(version_cluster, municipio)
][order(version_cluster, municipio)]

arrow::write_dataset(
  cluster_admin,
  path = file.path(out_base, "cluster_admin_territorial"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

data.table::fwrite(
  resumen,
  file.path(out_outputs, "cluster_admin_territorial_resumen.csv")
)
data.table::fwrite(
  resumen_municipio,
  file.path(out_outputs, "cluster_admin_territorial_resumen_municipio.csv")
)

print(resumen)
print(resumen_municipio)
