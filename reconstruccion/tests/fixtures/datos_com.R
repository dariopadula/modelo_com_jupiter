# Construye eventos pequenos con levantes antes/despues del corte y dos clusters.
# Entrada: ninguna. Salida: lista de fuentes crudas, referencia, rango y marcas.
rf_fixture_com <- function() {
  days <- c("2026-01-01 12:00:00", "2026-01-02 00:30:00", "2026-01-02 02:00:00", "2026-01-03 12:00:00")
  levante <- data.frame(levante_contenedor_id = rep(c("C0001", "C0002"), each = 4L), levante_fecha_levante = rep(days,
    2L), levante_fact = rep(days, 2L), levante_periodo = 1, levante_activo = 1L, levante_longitud = rep(c(5e+05,
    500200), each = 4L), levante_latitud = 6140000, levante_circuito = "fixture", levante_posicion_en_circuito = 1)
  point <- sf::st_transform(sf::st_as_sf(data.frame(x = 500010, y = 6140000), coords = c("x",
    "y"), crs = 32721), 4326)
  coordinates <- sf::st_coordinates(point)
  com <- data.frame(id = "E01", fecha_de_reclamo = "2026-01-01 14:00:00", fecha_resuelto = NA_character_,
    incidente = "Contenedor desbordado", repetido = FALSE, longitud = coordinates[1L,
      1L], latitud = coordinates[1L, 2L])
  members <- data.frame(version_cluster = "fixture_v1", cluster_id = c("A", "B"), punto_ref_id = c("P1",
    "P2"), x = c(5e+05, 500200), y = 6140000)
  list(raw_com = com, raw_levante = levante, cluster_members_ref = members, from = as.Date("2026-01-01"),
    through = as.Date("2026-01-03"), target_clusters = c("A", "B"), marks = list(source_id = "fixture",
      timezone = "America/Montevideo", complete_through = as.Date("2026-01-03"), available_through_timestamp = as.POSIXct("2026-01-03 23:00:00",
        tz = "America/Montevideo")))
}
