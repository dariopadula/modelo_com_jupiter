# Compara implementaciones migradas contra originales sobre fixtures pequenos.
# Entrada: raiz original explicita. Salida: informe, sin modificar datos originales.
all_args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", all_args, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) stop("Indicar raiz original")
old <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
.libPaths(c("C:/Users/dario/AppData/Local/R/win-library/4.5", .libPaths()))
library(data.table)
Sys.setenv(TZ = "America/Montevideo")
old_env <- new.env(parent = .GlobalEnv)
names <- c("preparar_datos_com", "definir_intervalos_actividad_contenedor", "preparar_datos_levante",
  "vecinos_cercanos", "asignar_puntos_a_clusters_referencia", "asignar_posiciones_levante_a_clusters",
  "asignar_com_a_contenedores_activos", "construir_base_cluster_dia", "construir_features_historicas_cluster_dia")
for (name in names) source(file.path(old, "funciones", paste0(name, ".R")), local = old_env)
source(file.path(root, "R/ingesta/cargar_componentes.R"))
rf_load_com_components(root)
source(file.path(root, "tests/fixtures/datos_com.R"))
fixture <- rf_fixture_com()
old_levante <- old_env$preparar_datos_levante(copy(fixture$raw_levante), fecha_min = fixture$from,
  fecha_max = fixture$through)
new_levante <- preparar_datos_levante(copy(fixture$raw_levante), fecha_min = fixture$from,
  fecha_max = fixture$through)
unchanged <- names(new_levante)[!grepl("_pred$|_pred_v2$|fecha_corte_prediccion", names(new_levante))]
stopifnot(isTRUE(all.equal(old_levante[, ..unchanged], new_levante[, ..unchanged])))
old_com <- old_env$preparar_datos_com(copy(fixture$raw_com))
new_com <- preparar_datos_com(copy(fixture$raw_com))
stopifnot(isTRUE(all.equal(old_com, new_com)))
old_map <- old_env$asignar_posiciones_levante_a_clusters(copy(new_levante), copy(fixture$cluster_members_ref))
new_map <- asignar_posiciones_levante_a_clusters(copy(new_levante), copy(fixture$cluster_members_ref))
stopifnot(isTRUE(all.equal(old_map, new_map)))
old_assigned <- old_env$asignar_com_a_contenedores_activos(copy(new_com), copy(new_levante),
  copy(new_map$contenedor_posicion_cluster_actual))
new_assigned <- asignar_com_a_contenedores_activos(copy(new_com), copy(new_levante), copy(new_map$contenedor_posicion_cluster_actual))
stopifnot(isTRUE(all.equal(old_assigned, new_assigned)))
old_base <- old_env$construir_base_cluster_dia(copy(new_levante), copy(new_assigned$asignaciones_com),
  copy(new_map$contenedor_posicion_cluster_actual), limitar_rango_fechas_com = FALSE)
new_base <- construir_base_cluster_dia(copy(new_levante), copy(new_assigned$asignaciones_com),
  copy(new_map$contenedor_posicion_cluster_actual), limitar_rango_fechas_com = FALSE)
stopifnot(isTRUE(all.equal(old_base, new_base)))
old_features <- old_env$construir_features_historicas_cluster_dia(copy(new_base$base_cluster_dia))
new_features <- construir_features_historicas_cluster_dia(copy(new_base$base_cluster_dia))
stopifnot(isTRUE(all.equal(old_features, new_features)))
cut_day <- as.IDate("2026-01-02")
old_cut <- old_levante[dia == cut_day & levante_contenedor_id == "C0001"]$fecha_corte_prediccion
new_cut <- new_levante[dia == cut_day & levante_contenedor_id == "C0001"]$fecha_corte_prediccion
stopifnot(as.numeric(difftime(new_cut, old_cut, units = "hours")) == 3)
jsonlite::write_json(list(status = "equivalencia_salvo_corte_aprobado", cutoff_difference_hours = 3,
  intentional_change = "01:00 America/Montevideo para nuevos levantes; no backfill historico"),
  file.path(root, "config/comparacion_funciones_r04.json"), pretty = TRUE, auto_unbox = TRUE)
cat("R04_ORIGINAL_OK: equivalencia de reglas; diferencia aprobada de corte +3h\n")
