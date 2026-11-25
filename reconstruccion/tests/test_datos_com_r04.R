# Comprueba reconstruccion real acotada contra features y asignaciones canonicas.
all_args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", all_args, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
.libPaths(c("C:/Users/dario/AppData/Local/R/win-library/4.5", .libPaths()))
source(file.path(root, "R/ingesta/cargar_componentes.R"))
rf_load_com_components(root)
source(file.path(root, "R/features/com_receta.R"))
source(file.path(root, "R/modelos/com_logistico.R"))
path <- file.path(root, "runtime/r04_com")
actual <- readRDS(file.path(path, "derivados.rds"))
expected <- data.table::as.data.table(readRDS(file.path(path, "features_referencia.rds")))
features <- data.table::copy(actual$features)
data.table::setorder(features, cluster_id, dia)
data.table::setorder(expected, cluster_id, dia)
stopifnot(nrow(features) == nrow(expected), identical(features$cluster_id, expected$cluster_id),
  identical(as.character(features$dia), as.character(expected$dia)))
columns <- intersect(names(expected), names(features))
differences <- lapply(columns, function(column) {
  x <- features[[column]]
  y <- expected[[column]]
  if (is.numeric(x) && !inherits(x, c("Date", "POSIXct"))) {
    mismatches <- sum(is.na(x) != is.na(y)) + sum(abs(x - y) > 1e-10, na.rm = TRUE)
    max_error <- if (all(is.na(x - y)))
      0 else max(abs(x - y), na.rm = TRUE)
  } else {
    mismatches <- sum(is.na(x) != is.na(y)) + sum(as.character(x) != as.character(y),
      na.rm = TRUE)
    max_error <- NA_real_
  }
  data.frame(variable = column, mismatches = mismatches, max_error = max_error)
})
differences <- do.call(rbind, differences)
utils::write.csv(differences, file.path(path, "comparacion_features.csv"), row.names = FALSE)
print(differences[differences$mismatches > 0, ])
stopifnot(all(differences$mismatches == 0L))

model <- readRDS(file.path(root, "runtime/r03_com/modelo_com.rds"))
entry <- readRDS(file.path(root, "runtime/r03_com/entrada.rds"))
pred <- rf_score_com(features, model, entry$day, entry$universe_n)
ref <- as.data.frame(readRDS(file.path(root, "runtime/r03_com/referencia_predicciones.rds")))
ref <- ref[match(pred$cluster_id, ref$cluster_id), ]
stopifnot(max(abs(pred$pred_prob - ref$pred_prob)) <= 1e-10)
stopifnot(actual$closure_status == "no_declarado", is.null(actual$marks$complete_through))
stopifnot(all(actual$controls$estado_fuente == "no_cerrado"))
assignments <- data.table::copy(actual$assignments)
assignment_ref <- data.table::as.data.table(readRDS(file.path(path, "asignaciones_referencia.rds")))
keys <- c("id", "dia", "x_com", "y_com")
data.table::setorderv(assignments, keys)
data.table::setorderv(assignment_ref, keys)
stopifnot(nrow(assignments) == nrow(assignment_ref))
for (column in c(keys, "cluster_id", "estado_asignacion_com")) {
  stopifnot(isTRUE(all.equal(assignments[[column]], assignment_ref[[column]], tolerance = 1e-10)))
}
# Congela la validacion del derivado concreto que podra consumir inferencia.
con <- file(file.path(path, "derivados.rds"), "rb")
hash <- unname(unclass(as.character(openssl::sha256(con))))
close(con)
jsonlite::write_json(list(status = "validado_bloque_historico", rows = nrow(features), columns = nrow(differences),
  assignment_rows = nrow(assignments), score_max_error = 0, derivados_sha256 = hash, scope = "historical_snapshot_march_50_clusters",
  closure_verified = FALSE, new_raw_cutoff_policy = "01:00_America/Montevideo_aprobado"),
  file.path(root, "config/validacion_r04.json"), pretty = TRUE, auto_unbox = TRUE)
cat("R04_DATOS_OK:", nrow(features), "filas;", nrow(differences), "variables; scores equivalentes\n")
