library(arrow)
library(dplyr)

path_base <- Sys.getenv(
  "APP_HISTORICO_PATH",
  unset = "../data/historico"
)

serie <- open_dataset(file.path(path_base, "serie_historica_com")) |>
  collect()
stopifnot(
  nrow(serie) == 26280L,
  all(c("montevideo", "barrio") %in% unique(serie$nivel_territorial)),
  !anyDuplicated(serie[c(
    "dia_objetivo", "nivel_territorial", "territorio_id", "escenario"
  )]),
  all(!is.na(serie$clusters_evaluados))
)

detalle <- open_dataset(
  file.path(path_base, "detalle_cluster_dia"),
  partitioning = hive_partition(
    dia_objetivo = date32(),
    modelo_id = utf8()
  )
)

fechas_com_cerradas <- detalle |>
  filter(modelo_id == "com_reclamo", estado_observacion == "cerrado") |>
  summarise(hasta = max(dia_objetivo)) |>
  collect()
fechas_zl_cerradas <- detalle |>
  filter(
    modelo_id == "zl_problema",
    estado_periodo_app == "historico_cerrado",
    hay_zl_visita_efectiva == 1L
  ) |>
  summarise(hasta = max(dia_objetivo)) |>
  collect()
stopifnot(
  fechas_com_cerradas$hasta[[1]] == as.Date("2026-05-22"),
  fechas_zl_cerradas$hasta[[1]] == as.Date("2026-05-22")
)

fecha <- as.Date("2026-05-24")
dia_com <- detalle |>
  filter(dia_objetivo == !!fecha, modelo_id == "com_reclamo") |>
  collect()
stopifnot(
  nrow(dia_com) > 0L,
  inherits(dia_com$dia_objetivo, "Date"),
  all(dia_com$dia_objetivo == fecha),
  all(dia_com$modelo_id == "com_reclamo")
)

cat("HISTORICO_OK\n")
