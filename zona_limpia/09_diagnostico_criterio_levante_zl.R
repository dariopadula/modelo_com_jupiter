library(arrow)
library(data.table)

path_features <- "data/processed/modelo_cluster_dia/features_cluster_dia"
path_comparacion_zl <- "data/processed/zona_limpia/comparacion_com_zona_limpia_cluster_dia"
path_cluster_admin <- "data/processed/cluster_territorial/cluster_admin_territorial"
out_outputs <- "zona_limpia/outputs"

target_version_cluster <- Sys.getenv("VERSION_CLUSTER", unset = NA_character_)
meses_analisis <- as.integer(strsplit(
  Sys.getenv("MESES_ANALISIS_ZL_LEVANTE", unset = "202510,202511,202512,202603,202604,202605"),
  ","
)[[1]])

dir.create(out_outputs, recursive = TRUE, showWarnings = FALSE)

truncar <- function(x, min_val = 0, max_val = 7) {
  pmin(pmax(x, min_val), max_val)
}

cuantil_seguro <- function(x, p) {
  as.numeric(stats::quantile(x, p, na.rm = TRUE, names = FALSE))
}

features <- as.data.table(arrow::open_dataset(path_features, format = "parquet"))
comparacion_zl <- as.data.table(arrow::open_dataset(path_comparacion_zl, format = "parquet"))
cluster_admin <- as.data.table(arrow::open_dataset(path_cluster_admin, format = "parquet"))

if (is.na(target_version_cluster) || target_version_cluster == "") {
  versiones <- sort(unique(features$version_cluster))
  target_version_cluster <- versiones[length(versiones)]
}

features[, version_cluster := as.character(version_cluster)]
features[, cluster_id := as.character(cluster_id)]
comparacion_zl[, version_cluster := as.character(version_cluster)]
comparacion_zl[, cluster_id := as.character(cluster_id)]
cluster_admin[, version_cluster := as.character(version_cluster)]
cluster_admin[, cluster_id := as.character(cluster_id)]

features <- features[
  version_cluster == target_version_cluster &
    anio_mes %in% meses_analisis,
  .(
    cluster_id,
    dia = as.IDate(dia),
    anio_mes,
    version_cluster,
    n_contenedores_activos,
    mean_tiempo_desde_ultimo_levante_pred,
    median_tiempo_desde_ultimo_levante_pred,
    max_tiempo_desde_ultimo_levante_pred,
    mean_levante_periodo,
    max_levante_periodo,
    mean_ratio_tiempo_periodo_pred,
    median_ratio_tiempo_periodo_pred,
    max_ratio_tiempo_periodo_pred
  )
]

comparacion_zl <- comparacion_zl[
  version_cluster == target_version_cluster &
    anio_mes %in% meses_analisis,
  .(
    cluster_id,
    dia = as.IDate(dia),
    hay_zl_visita_efectiva,
    hay_zl_problema_comparable,
    hay_zl_voluminosos,
    hay_com
  )
]

cluster_admin <- cluster_admin[
  version_cluster == target_version_cluster,
  .(cluster_id, municipio, ccz, nombre_barrio_ine)
]

base <- cluster_admin[
  features,
  on = "cluster_id"
]
base <- comparacion_zl[
  base,
  on = .(cluster_id, dia)
]

for (col in c("hay_zl_visita_efectiva", "hay_zl_problema_comparable", "hay_zl_voluminosos", "hay_com")) {
  base[is.na(get(col)), (col) := FALSE]
}

base[, problema_real_observado := hay_com | hay_zl_problema_comparable]

base[, `:=`(
  exceso_mean_tiempo_periodo_pred =
    mean_tiempo_desde_ultimo_levante_pred - mean_levante_periodo,
  exceso_max_tiempo_periodo_pred =
    max_tiempo_desde_ultimo_levante_pred - max_levante_periodo
)]

base[, `:=`(
  exceso_mean_tiempo_periodo_pred_pos =
    pmax(exceso_mean_tiempo_periodo_pred, 0),
  exceso_max_tiempo_periodo_pred_pos =
    pmax(exceso_max_tiempo_periodo_pred, 0),
  exceso_mean_tiempo_periodo_pred_trunc_7 =
    truncar(exceso_mean_tiempo_periodo_pred, 0, 7),
  exceso_max_tiempo_periodo_pred_trunc_7 =
    truncar(exceso_max_tiempo_periodo_pred, 0, 7),
  mean_ratio_tiempo_periodo_pred_trunc_3 =
    truncar(mean_ratio_tiempo_periodo_pred, 0, 3),
  max_ratio_tiempo_periodo_pred_trunc_3 =
    truncar(max_ratio_tiempo_periodo_pred, 0, 3)
)]

variables_levante <- c(
  "mean_tiempo_desde_ultimo_levante_pred",
  "median_tiempo_desde_ultimo_levante_pred",
  "max_tiempo_desde_ultimo_levante_pred",
  "mean_levante_periodo",
  "mean_ratio_tiempo_periodo_pred",
  "median_ratio_tiempo_periodo_pred",
  "max_ratio_tiempo_periodo_pred",
  "exceso_mean_tiempo_periodo_pred",
  "exceso_mean_tiempo_periodo_pred_pos",
  "exceso_mean_tiempo_periodo_pred_trunc_7",
  "exceso_max_tiempo_periodo_pred",
  "exceso_max_tiempo_periodo_pred_pos",
  "exceso_max_tiempo_periodo_pred_trunc_7"
)

resumen_variables <- rbindlist(lapply(variables_levante, function(var) {
  base[
    ,
    .(
      variable = var,
      n = sum(!is.na(get(var))),
      media = mean(get(var), na.rm = TRUE),
      mediana = stats::median(get(var), na.rm = TRUE),
      p25 = cuantil_seguro(get(var), 0.25),
      p75 = cuantil_seguro(get(var), 0.75),
      p90 = cuantil_seguro(get(var), 0.90),
      tasa_visita_zl = mean(hay_zl_visita_efectiva),
      tasa_problema_real = mean(problema_real_observado)
    ),
    by = .(hay_zl_visita_efectiva)
  ]
}), fill = TRUE)

deciles_exceso <- copy(base[!is.na(exceso_mean_tiempo_periodo_pred_trunc_7)])
deciles_exceso[
  ,
  decil_exceso_mean_trunc_7 := pmin(
    10L,
    pmax(1L, ceiling(frank(exceso_mean_tiempo_periodo_pred_trunc_7, ties.method = "average") / .N * 10))
  )
]

resumen_decil_exceso <- deciles_exceso[
  ,
  .(
    n_cluster_dia = .N,
    exceso_min = min(exceso_mean_tiempo_periodo_pred_trunc_7, na.rm = TRUE),
    exceso_media = mean(exceso_mean_tiempo_periodo_pred_trunc_7, na.rm = TRUE),
    exceso_max = max(exceso_mean_tiempo_periodo_pred_trunc_7, na.rm = TRUE),
    visitas_zl = sum(hay_zl_visita_efectiva),
    tasa_visita_zl = mean(hay_zl_visita_efectiva),
    problemas_zl = sum(hay_zl_problema_comparable),
    tasa_problema_zl_en_visitas = sum(hay_zl_problema_comparable) / pmax(sum(hay_zl_visita_efectiva), 1),
    problemas_reales = sum(problema_real_observado),
    tasa_problema_real = mean(problema_real_observado)
  ),
  by = decil_exceso_mean_trunc_7
][order(decil_exceso_mean_trunc_7)]

base[
  ,
  bin_exceso_mean_trunc_7 := cut(
    exceso_mean_tiempo_periodo_pred_trunc_7,
    breaks = c(-Inf, 0, 1, 2, 3, 5, 7, Inf),
    labels = c("0", "0-1", "1-2", "2-3", "3-5", "5-7", ">7"),
    right = TRUE
  )
]

resumen_bin_exceso <- base[
  !is.na(bin_exceso_mean_trunc_7),
  .(
    n_cluster_dia = .N,
    visitas_zl = sum(hay_zl_visita_efectiva),
    tasa_visita_zl = mean(hay_zl_visita_efectiva),
    problemas_zl = sum(hay_zl_problema_comparable),
    tasa_problema_zl_en_visitas = sum(hay_zl_problema_comparable) / pmax(sum(hay_zl_visita_efectiva), 1),
    problemas_reales = sum(problema_real_observado),
    tasa_problema_real = mean(problema_real_observado)
  ),
  by = bin_exceso_mean_trunc_7
][order(bin_exceso_mean_trunc_7)]

resumen_municipio_exceso <- base[
  ,
  .(
    n_cluster_dia = .N,
    visitas_zl = sum(hay_zl_visita_efectiva),
    tasa_visita_zl = mean(hay_zl_visita_efectiva),
    exceso_mean_medio = mean(exceso_mean_tiempo_periodo_pred_trunc_7, na.rm = TRUE),
    exceso_mean_mediana = stats::median(exceso_mean_tiempo_periodo_pred_trunc_7, na.rm = TRUE),
    ratio_mean_medio = mean(mean_ratio_tiempo_periodo_pred, na.rm = TRUE),
    tasa_problema_zl_en_visitas = sum(hay_zl_problema_comparable) / pmax(sum(hay_zl_visita_efectiva), 1)
  ),
  by = municipio
][order(-tasa_visita_zl)]

resumen_ccz_exceso <- base[
  ,
  .(
    n_cluster_dia = .N,
    visitas_zl = sum(hay_zl_visita_efectiva),
    tasa_visita_zl = mean(hay_zl_visita_efectiva),
    exceso_mean_medio = mean(exceso_mean_tiempo_periodo_pred_trunc_7, na.rm = TRUE),
    exceso_mean_mediana = stats::median(exceso_mean_tiempo_periodo_pred_trunc_7, na.rm = TRUE),
    ratio_mean_medio = mean(mean_ratio_tiempo_periodo_pred, na.rm = TRUE),
    tasa_problema_zl_en_visitas = sum(hay_zl_problema_comparable) / pmax(sum(hay_zl_visita_efectiva), 1)
  ),
  by = .(municipio, ccz)
][order(-tasa_visita_zl)]

data.table::fwrite(
  resumen_variables,
  file.path(out_outputs, "diagnostico_levante_zl_resumen_variables.csv")
)
data.table::fwrite(
  resumen_decil_exceso,
  file.path(out_outputs, "diagnostico_levante_zl_decil_exceso_mean_trunc_7.csv")
)
data.table::fwrite(
  resumen_bin_exceso,
  file.path(out_outputs, "diagnostico_levante_zl_bin_exceso_mean_trunc_7.csv")
)
data.table::fwrite(
  resumen_municipio_exceso,
  file.path(out_outputs, "diagnostico_levante_zl_municipio.csv")
)
data.table::fwrite(
  resumen_ccz_exceso,
  file.path(out_outputs, "diagnostico_levante_zl_ccz.csv")
)

print(resumen_variables[order(variable, -hay_zl_visita_efectiva)])
print(resumen_bin_exceso)
print(resumen_decil_exceso)
print(resumen_municipio_exceso)
