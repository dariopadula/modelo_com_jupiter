library(arrow)
library(data.table)
library(sf)

path_segmentos <- "shp/Marco2011_SEG_Montevideo_Total/Marco2011_SEG_Montevideo_Total.shp"
path_cluster_actual <- "data/processed/cluster_update_check/contenedor_posicion_cluster_actual"
out_base <- "data/processed/cluster_territorial"
out_outputs <- "data/processed/cluster_territorial/resumen"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
estados_cluster_validos <- c("referencia", "asignado", "revision")
crs_objetivo <- 32721

dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
dir.create(out_outputs, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(path_segmentos)) {
  stop("No existe el shape de segmentos censales: ", path_segmentos)
}

segmentos <- sf::st_read(path_segmentos, quiet = TRUE)
if (is.na(sf::st_crs(segmentos))) {
  stop("El shape de segmentos censales no tiene CRS definido.")
}
segmentos <- sf::st_transform(segmentos, crs_objetivo)

segmentos[, "area_segmento_m2"] <- as.numeric(sf::st_area(segmentos))
segmentos[, "area_segmento_km2"] <- segmentos$area_segmento_m2 / 1e6

dividir_seguro <- function(numerador, denominador) {
  data.table::fifelse(denominador > 0, numerador / denominador, NA_real_)
}

segmentos_dt <- data.table::as.data.table(sf::st_drop_geometry(segmentos))
segmentos_dt[, `:=`(
  codseg = as.integer(CODSEG),
  seccion = as.integer(SECCION),
  segmento = as.integer(SEGMENTO),
  localidad = as.integer(LOCALIDAD),
  nombre_departamento = as.character(NOMBDEPTO),
  nombre_localidad = as.character(NOMBLOC),
  poblacion_segmento = as.numeric(P_TOT),
  hogares_segmento = as.numeric(H_TOT),
  viviendas_segmento = as.numeric(V_TOT),
  viviendas_ocupadas_segmento = as.numeric(V_TOT_OC),
  hogares_nbi_no = as.numeric(NBI_No),
  hogares_nbi_si = as.numeric(NBI_Si),
  hogares_nbi_una = as.numeric(NBI_Una),
  hogares_nbi_dos = as.numeric(NBI_Dos),
  hogares_nbi_tres_o_mas = as.numeric(NBI_T_o_M),
  porc_nbi_segmento = as.numeric(PORC_NBI),
  porc_asentamiento_nbi_segmento = as.numeric(PORC_AS_NB),
  porc_vivienda_inadecuada_segmento = as.numeric(PORC_VI),
  densidad_pob_km2 = dividir_seguro(as.numeric(P_TOT), area_segmento_km2),
  densidad_hog_km2 = dividir_seguro(as.numeric(H_TOT), area_segmento_km2),
  densidad_viv_km2 = dividir_seguro(as.numeric(V_TOT), area_segmento_km2)
)]

cols_segmento <- c(
  "codseg",
  "seccion",
  "segmento",
  "localidad",
  "nombre_departamento",
  "nombre_localidad",
  "area_segmento_m2",
  "area_segmento_km2",
  "poblacion_segmento",
  "hogares_segmento",
  "viviendas_segmento",
  "viviendas_ocupadas_segmento",
  "hogares_nbi_no",
  "hogares_nbi_si",
  "hogares_nbi_una",
  "hogares_nbi_dos",
  "hogares_nbi_tres_o_mas",
  "porc_nbi_segmento",
  "porc_asentamiento_nbi_segmento",
  "porc_vivienda_inadecuada_segmento",
  "densidad_pob_km2",
  "densidad_hog_km2",
  "densidad_viv_km2"
)

segmentos_vars <- segmentos_dt[, ..cols_segmento]
segmentos_join <- segmentos[, c(
  "CODSEG",
  "P_TOT",
  "H_TOT",
  "V_TOT",
  "V_TOT_OC",
  "NBI_No",
  "NBI_Si",
  "NBI_Una",
  "NBI_Dos",
  "NBI_T_o_M",
  "PORC_NBI",
  "PORC_AS_NB",
  "PORC_VI",
  "area_segmento_m2",
  "area_segmento_km2"
)]

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

if (nrow(contenedor_posicion_cluster) == 0L) {
  stop("No hay mapeo contenedor-cluster para version_cluster = ", target_version_cluster)
}

posiciones_cluster <- data.table::copy(contenedor_posicion_cluster[
  !is.na(cluster_id) &
    !is.na(x) & !is.na(y) &
    estado_asignacion_cluster %in% estados_cluster_validos
])

if (nrow(posiciones_cluster) == 0L) {
  stop("No hay posiciones validas de cluster para version_cluster = ", target_version_cluster)
}

cluster_centroide <- posiciones_cluster[
  ,
  .(
    x_cluster = mean(as.numeric(x), na.rm = TRUE),
    y_cluster = mean(as.numeric(y), na.rm = TRUE),
    n_posiciones_cluster = .N,
    n_contenedores_cluster = data.table::uniqueN(levante_contenedor_id),
    n_posiciones_referencia = sum(estado_asignacion_cluster == "referencia"),
    n_posiciones_asignado = sum(estado_asignacion_cluster == "asignado"),
    n_posiciones_revision = sum(estado_asignacion_cluster == "revision")
  ),
  by = cluster_id
]

cluster_centroide_sf <- sf::st_as_sf(
  cluster_centroide,
  coords = c("x_cluster", "y_cluster"),
  crs = crs_objetivo,
  remove = FALSE
)

cluster_centroide_seg <- sf::st_join(
  cluster_centroide_sf,
  segmentos_join,
  join = sf::st_within,
  left = TRUE
)
cluster_centroide_dt <- data.table::as.data.table(sf::st_drop_geometry(cluster_centroide_seg))
data.table::setnames(cluster_centroide_dt, "CODSEG", "codseg_centroide")

posiciones_sf <- sf::st_as_sf(
  posiciones_cluster,
  coords = c("x", "y"),
  crs = crs_objetivo,
  remove = FALSE
)
posiciones_seg <- sf::st_join(
  posiciones_sf,
  segmentos[, c("CODSEG")],
  join = sf::st_within,
  left = TRUE
)
posiciones_seg_dt <- data.table::as.data.table(sf::st_drop_geometry(posiciones_seg))
data.table::setnames(posiciones_seg_dt, "CODSEG", "codseg_posicion")

conteo_segmentos_cluster <- posiciones_seg_dt[
  !is.na(codseg_posicion),
  .(n_posiciones_segmento = .N),
  by = .(cluster_id, codseg_posicion)
]

segmento_principal <- conteo_segmentos_cluster[
  order(cluster_id, -n_posiciones_segmento, codseg_posicion)
][
  ,
  .SD[1],
  by = cluster_id
]
data.table::setnames(segmento_principal, "codseg_posicion", "codseg_principal")

diagnostico_mix <- posiciones_seg_dt[
  ,
  .(
    n_posiciones_cluster = .N,
    n_posiciones_sin_segmento = sum(is.na(codseg_posicion)),
    n_segmentos_posiciones = data.table::uniqueN(codseg_posicion, na.rm = TRUE)
  ),
  by = cluster_id
]

diagnostico_mix <- segmento_principal[
  diagnostico_mix,
  on = "cluster_id"
]
diagnostico_mix[, pct_posiciones_segmento_principal := dividir_seguro(
  n_posiciones_segmento,
  n_posiciones_cluster
)]
diagnostico_mix[, cluster_multisegmento := n_segmentos_posiciones > 1]

cluster_territorial <- diagnostico_mix[
  cluster_centroide_dt,
  on = "cluster_id"
]

cluster_territorial <- segmentos_vars[
  cluster_territorial,
  on = c(codseg = "codseg_centroide")
]
data.table::setnames(cluster_territorial, "codseg", "codseg_centroide")

cluster_territorial[, version_cluster := target_version_cluster]

cols_orden <- c(
  "version_cluster",
  "cluster_id",
  "x_cluster",
  "y_cluster",
  "codseg_centroide",
  "codseg_principal",
  "cluster_multisegmento",
  "n_segmentos_posiciones",
  "pct_posiciones_segmento_principal",
  "n_posiciones_cluster",
  "n_contenedores_cluster",
  "n_posiciones_sin_segmento",
  "n_posiciones_referencia",
  "n_posiciones_asignado",
  "n_posiciones_revision",
  setdiff(cols_segmento, "codseg")
)
cluster_territorial <- cluster_territorial[, ..cols_orden]

resumen <- data.table::data.table(
  version_cluster = target_version_cluster,
  clusters = nrow(cluster_territorial),
  clusters_sin_segmento_centroide = sum(is.na(cluster_territorial$codseg_centroide)),
  pct_clusters_sin_segmento_centroide = mean(is.na(cluster_territorial$codseg_centroide)),
  segmentos_centroide = data.table::uniqueN(cluster_territorial$codseg_centroide, na.rm = TRUE),
  clusters_multisegmento = sum(cluster_territorial$cluster_multisegmento, na.rm = TRUE),
  pct_clusters_multisegmento = mean(cluster_territorial$cluster_multisegmento, na.rm = TRUE),
  max_segmentos_posiciones = max(cluster_territorial$n_segmentos_posiciones, na.rm = TRUE),
  min_pct_posiciones_segmento_principal = min(
    cluster_territorial$pct_posiciones_segmento_principal,
    na.rm = TRUE
  )
)

resumen_segmentos <- cluster_territorial[
  ,
  .(
    clusters = .N,
    n_posiciones_cluster = sum(n_posiciones_cluster),
    poblacion_segmento = data.table::first(poblacion_segmento),
    hogares_segmento = data.table::first(hogares_segmento),
    viviendas_segmento = data.table::first(viviendas_segmento),
    porc_nbi_segmento = data.table::first(porc_nbi_segmento),
    densidad_pob_km2 = data.table::first(densidad_pob_km2)
  ),
  by = codseg_centroide
][order(-clusters)]

arrow::write_dataset(
  cluster_territorial,
  path = file.path(out_base, "cluster_segmento_censal"),
  format = "parquet",
  partitioning = "version_cluster",
  existing_data_behavior = "delete_matching",
  compression = "zstd"
)

data.table::fwrite(
  resumen,
  file.path(out_outputs, "cluster_segmento_censal_resumen.csv")
)
data.table::fwrite(
  resumen_segmentos,
  file.path(out_outputs, "cluster_segmento_censal_resumen_segmentos.csv")
)

print(resumen)
print(resumen_segmentos[1:10])
