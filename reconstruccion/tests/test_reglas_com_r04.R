# Casos de negocio independientes de datos grandes o conexiones.
all_args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", all_args, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
.libPaths(c("C:/Users/dario/AppData/Local/R/win-library/4.5", .libPaths()))
source(file.path(root, "R/ingesta/cargar_componentes.R"))
rf_load_com_components(root)
source(file.path(root, "R/features/com_receta.R"))
source(file.path(root, "tests/fixtures/datos_com.R"))
Sys.setenv(TZ = "America/Montevideo")
fixture <- rf_fixture_com()
count <- 0L
# Registra una asercion de negocio satisfactoria.  Entrada: expresion logica. Salida:
# contador actualizado o fallo de prueba.
check <- function(value) {
  stopifnot(isTRUE(value))
  count <<- count + 1L
}
levante <- preparar_datos_levante(data.table::copy(fixture$raw_levante), fecha_min = fixture$from,
  fecha_max = fixture$through)
cut <- levante[dia == data.table::as.IDate("2026-01-02") & levante_contenedor_id == "C0001"]
check(format(cut$fecha_corte_prediccion, tz = "America/Montevideo") == "2026-01-02 01:00:00")
check(format(cut$fecha_ultimo_levante_pred, tz = "America/Montevideo") == "2026-01-02 00:30:00")
result <- rf_process_raw_com(fixture)
check(nrow(result$features) == 6L)
check(all(result$base[dia == data.table::as.IDate("2026-01-03")]$n_reclamos == 0L))
check(identical(result$cutoff_policy, "01:00_America/Montevideo_R04"))
check(all(result$features[dia == data.table::as.IDate("2026-01-01")]$dias_historia_observada_cluster ==
  0))
zero <- fixture
zero$raw_com <- fixture$raw_com[0, ]
zero_result <- rf_process_raw_com(zero)
check(nrow(zero_result$features) == 6L && all(zero_result$features$n_reclamos == 0L))

points <- data.frame(x = c(500050, 500075, 500150), y = 6140000)
assigned <- asignar_puntos_a_clusters_referencia(points, fixture$cluster_members_ref[1L,
  ])
check(identical(assigned$estado_asignacion, c("asignado", "revision", "pendiente")))
check(is.na(assigned$cluster_id_asignado[[3L]]))

day <- data.table::as.IDate("2026-01-02")
candidates <- data.table::copy(levante[dia == day])
data.table::setorder(candidates, levante_contenedor_id)
candidates[, `:=`(x = c(5e+05, 500020), y = 6140000, contenedor_activo_dia = TRUE, contenedor_dia_elegible_modelo = c(FALSE,
  TRUE))]
map <- data.table::data.table(levante_contenedor_id = c("C0001", "C0002"), x = c(5e+05, 500020),
  y = 6140000, cluster_id = c("A", "B"), version_cluster = "fixture_v1")
claim <- data.table::data.table(id = "c", dia = day, x = 5e+05, y = 6140000)
assignment <- asignar_com_a_contenedores_activos(claim, candidates, map)$asignaciones_com
check(identical(assignment$cluster_id, "B"))

history <- result$features
lagged <- aplicar_rezago_historia_reclamos(history, 2L)
changed <- data.table::copy(history)
changed[dia >= day, `:=`(n_reclamos = 999L, tuvo_reclamo = TRUE)]
lagged_changed <- aplicar_rezago_historia_reclamos(changed, 2L)
check(identical(lagged[dia == day + 1L]$n_reclamos_lag1, lagged_changed[dia == day + 1L]$n_reclamos_lag1))
check(identical(lagged[dia == day + 1L]$n_reclamos_sum_7d, lagged_changed[dia == day + 1L]$n_reclamos_sum_7d))
corrected <- data.table::copy(history)
corrected[cluster_id == "A" & dia == day - 1L, n_reclamos := n_reclamos + 1L]
corrected <- aplicar_rezago_historia_reclamos(corrected, 2L)
check(corrected[cluster_id == "A" & dia == day + 1L]$n_reclamos_lag1 == lagged[cluster_id ==
  "A" & dia == day + 1L]$n_reclamos_lag1 + 1L)
invalid <- fixture$marks
invalid$complete_through <- "2026-01-03"
check(inherits(try(rf_source_marks(invalid), silent = TRUE), "try-error"))
invalid$complete_through <- NULL
invalid["complete_through"] <- list(NULL)
check(rf_source_marks(invalid))
check(all(result$controls[dia == data.table::as.IDate("2026-01-03")]$estado_fuente == "sin_eventos"))
cat("R04_REGLAS_OK:", count, "comprobaciones\n")
