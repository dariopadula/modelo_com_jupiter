# Verifica scoring incremental COM con el bloque R04 y marcas sinteticas declaradas.
all_arguments <- commandArgs(trailingOnly = FALSE)
test_path <- sub("^--file=", "", grep("^--file=", all_arguments, value = TRUE)[[1L]])
project_root <- normalizePath(file.path(dirname(test_path), ".."), winslash = "/", mustWork = TRUE)
invisible(parse(file = file.path(project_root, "scripts/scoring_com_incremental.R")))
library_version <- paste0(R.version$major, ".", sub("\\..*$", "", R.version$minor))
user_library <- Sys.getenv("RF_R_LIBRARY", unset = Sys.getenv("R_LIBS_USER", unset = ""))
if ((!nzchar(user_library) || !dir.exists(user_library)) && identical(Sys.info()[["sysname"]], "Windows") && nzchar(Sys.getenv("USERPROFILE"))) {
  user_library <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "R", "win-library", library_version)
}
if (nzchar(user_library) && dir.exists(user_library)) {
  .libPaths(c(user_library, .libPaths()))
}
source(file.path(project_root, "R/features/com_receta.R"))
source(file.path(project_root, "R/modelos/com_logistico.R"))
source(file.path(project_root, "R/operacion/estado_com.R"))
source(file.path(project_root, "R/operacion/scoring_incremental_com.R"))

features <- readRDS(file.path(project_root, "runtime/r04_com/derivados.rds"))$features
model <- readRDS(file.path(project_root, "runtime/r03_com/modelo_com.rds"))
available_days <- sort(unique(as.Date(features$dia)))
end_day <- available_days[[length(available_days)]]
first_day <- available_days[[length(available_days) - 3L]]
target_days <- available_days[available_days > first_day & available_days <= end_day]
stopifnot(length(target_days) == 3L, all(diff(target_days) == 1))
initial_state <- rf_build_com_state(features[as.Date(features$dia) <= first_day, ], first_day, first_day - 2L)
marks <- list(
  levante_available_through = as.POSIXct(paste(end_day, "02:00:00"), tz = "America/Montevideo"),
  com_complete_through = end_day,
  timezone = "America/Montevideo",
  cutoff_policy = "01:00_America/Montevideo_R04"
)

# El bloque de tres días debe coincidir con tres ejecuciones consecutivas.
block <- rf_run_com_incremental(features, model, initial_state, marks = marks, through_day = end_day)
sequential <- NULL
sequential_state <- initial_state
for (target_day in target_days) {
  sequential <- rf_run_com_incremental(features, model, sequential_state,
    predictions = if (is.null(sequential)) {
      NULL
    } else {
      sequential$predictions
    },
    marks = marks, through_day = target_day)
  sequential_state <- sequential$state
}
block_scores <- block$predictions[as.Date(block$predictions$dia_objetivo) %in% target_days,
  c("dia_objetivo", "cluster_id", "pred_prob", "ranking_dia")]
sequential_scores <- sequential$predictions[as.Date(sequential$predictions$dia_objetivo) %in% target_days,
  c("dia_objetivo", "cluster_id", "pred_prob", "ranking_dia")]
data.table::setorder(block_scores, dia_objetivo, cluster_id)
data.table::setorder(sequential_scores, dia_objetivo, cluster_id)
stopifnot(isTRUE(all.equal(block_scores, sequential_scores, tolerance = 0)))
stopifnot(identical(as.character(block$state_day), as.character(end_day)), nrow(block$controls) == 3L,
  all(block$controls$estado_prediccion == "generada"))

# Repetir un bloque ya procesado conserva scores y deja controles vacíos.
repeated <- rf_run_com_incremental(features, model, block$state, predictions = block$predictions,
  marks = marks, through_day = end_day)
score_columns <- c("dia_objetivo", "cluster_id", "pred_prob", "ranking_dia")
stopifnot(isTRUE(all.equal(repeated$predictions[, ..score_columns], block$predictions[, ..score_columns], tolerance = 0)),
  nrow(repeated$controls) == 0L)

# El cierre atrasado bloquea el primer día y no avanza el estado.
stale_marks <- marks
stale_marks$com_complete_through <- as.Date(first_day - 2L)
stale <- rf_run_com_incremental(features, model, initial_state, marks = stale_marks, through_day = end_day)
stopifnot(identical(as.character(stale$state_day), as.character(first_day)), nrow(stale$predictions) == 0L,
  stale$controls$motivo[[1L]] == "com_no_cerrado_para_features",
  all(stale$controls$motivo[-1L] == "dia_anterior_bloqueado"))

# El cierre posterior incorpora observados sin tocar scores emitidos.
first_scores <- block$predictions[as.Date(block$predictions$dia_objetivo) == target_days[[1L]], ]
delayed_marks <- marks
delayed_marks$com_complete_through <- as.Date(target_days[[1L]])
first_state <- rf_build_com_state(features[as.Date(features$dia) <= target_days[[1L]], ],
  target_days[[1L]], target_days[[1L]] - 2L)
late <- rf_run_com_incremental(features, model, first_state, predictions = first_scores,
  marks = delayed_marks, through_day = target_days[[1L]])
comparison <- merge(first_scores[, ..score_columns], late$predictions[, ..score_columns],
  by = c("dia_objetivo", "cluster_id"), suffixes = c("_before", "_after"))
stopifnot(isTRUE(all.equal(comparison$pred_prob_before, comparison$pred_prob_after, tolerance = 0)),
  all(late$predictions$estado_observacion == "cerrado"),
  all(!is.na(late$predictions$tuvo_reclamo_observado)))

# Los cierres ausentes y la politica temporal incorrecta detienen el scoring.
missing_close <- marks
missing_close$com_complete_through <- NULL
stopifnot(inherits(try(rf_run_com_incremental(features, model, initial_state, marks = missing_close,
  through_day = end_day), silent = TRUE), "try-error"))
wrong_cutoff <- marks
wrong_cutoff$cutoff_policy <- "corte_historico_heredado"
stopifnot(inherits(try(rf_run_com_incremental(features, model, initial_state, marks = wrong_cutoff,
  through_day = end_day), silent = TRUE), "try-error"))

cat("R05_OK: bloque/secuencia, idempotencia, bloqueo por cierre, observados tardios y cortes\n")
