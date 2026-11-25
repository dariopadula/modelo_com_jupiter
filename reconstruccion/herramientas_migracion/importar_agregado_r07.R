# Importa los modelos A0/P3 congelados y una fecha de comparacion, sin entrenar.
# Recorre CSV por bloques para no materializar toda la historia de features.
# Uso: importar_agregado_r07.R <raiz_original> <directorio_nuevo> <AAAA-MM-DD>

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 3L) {
  stop("Uso: importar_agregado_r07.R <raiz_original> <directorio_nuevo> <AAAA-MM-DD>")
}
script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/")
source(file.path(root, "R/configuracion/runtime_r07.R"), encoding = "UTF-8")
rf_init_r07()
library(data.table)
legacy_root <- normalizePath(arguments[[1L]], winslash = "/", mustWork = TRUE)
output <- arguments[[2L]]
day <- as.character(as.Date(arguments[[3L]]))
if (dir.exists(output) || file.exists(output) || is.na(day)) {
  stop("Se requiere una fecha valida y un destino nuevo")
}

# Lee unicamente registros del dia pedido; los CSV originales son tablas sin campos multilinea.
read_day <- function(path, day) {
  connection <- file(path, "rt", encoding = "UTF-8")
  on.exit(close(connection))
  header <- readLines(connection, n = 1L)
  pieces <- list()
  repeat {
    lines <- readLines(connection, n = 10000L, warn = FALSE)
    if (!length(lines)) {
      break
    }
    block <- fread(text = paste(c(header, lines), collapse = "\n"), encoding = "UTF-8", showProgress = FALSE)
    selected <- block[as.character(dia_objetivo) == day]
    if (nrow(selected)) {
      pieces[[length(pieces) + 1L]] <- selected
    }
  }
  rbindlist(pieces, use.names = TRUE)
}

manifest <- jsonlite::fromJSON(file.path(root, "config/referencia_local_r01.json"))
paths <- c(a0 = "outputs/prueba_xgboost_correccion_estructural_com/modelo_A0_final.rds",
  p3 = "outputs/comparacion_poda_xgboost_com/modelo_P3_compacto.rds")
for (relative in paths) {
  connection <- file(file.path(legacy_root, relative), "rb")
  actual <- as.character(openssl::sha256(connection))
  close(connection)
  expected <- manifest$files$sha256[manifest$files$path == relative]
  if (length(expected) != 1L || actual != expected) {
    stop("El modelo original no coincide con el hash R01: ", relative)
  }
}
a0 <- readRDS(file.path(legacy_root, paths[["a0"]]))
p3 <- readRDS(file.path(legacy_root, paths[["p3"]]))
base <- read_day(file.path(legacy_root,
  "outputs/comparacion_ventanas_propension_xgboost_com/base_segmento_dia_ventanas.csv"), day)
if (!nrow(base) || any(base$split_modelo == "entrenamiento")) {
  stop("Se requiere una muestra de validacion/test fuera del entrenamiento A0")
}
base[, `:=`(dia_objetivo = as.IDate(dia_objetivo), segmento = as.character(segmento),
  delta_q_7_60 = media_q_7 - media_q_60, version_cluster = manifest$cluster_version)]
holidays <- new.env(parent = baseenv())
sys.source(file.path(legacy_root, "data/reference/feriados/feriados.R"), holidays)
base[, es_feriado := as.integer(dia_objetivo %in% as.IDate(holidays$diasDesc))]
daily <- read_day(file.path(legacy_root, "outputs/comparacion_poda_xgboost_com/predicciones_diarias.csv"), day)
neighborhood <- read_day(file.path(legacy_root, "outputs/comparacion_poda_xgboost_com/predicciones_barrio_dia.csv"), day)
daily <- daily[escenario == "P3_compacto"]
neighborhood <- neighborhood[escenario == "P3_compacto"]
bundle <- list(a0 = a0, p3 = p3, scenario = "P3_compacto", a0_trained_until = as.IDate("2025-12-31"),
  version_cluster = manifest$cluster_version, source_reference_id = manifest$reference_id)
dir.create(output, recursive = TRUE)
saveRDS(bundle, file.path(output, "bundle.rds"))
saveRDS(list(base = base, daily_reference = daily, neighborhood_reference = neighborhood,
  day = day, source = "snapshot_csv_legado_solo_equivalencia"), file.path(output, "muestra.rds"))
cat("R07_REFERENCE_IMPORTED: day=", day, " segment_rows=", nrow(base), "\n", sep = "")
