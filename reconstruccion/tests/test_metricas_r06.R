# Verifica AUC con productos de clases mayores que el limite entero, sin entrenar.
arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/")
user_library <- Sys.getenv("RF_R_LIBRARY", unset = file.path(Sys.getenv("USERPROFILE"),
  "AppData", "Local", "R", "win-library", paste0(R.version$major, ".", sub("\\..*$", "", R.version$minor))))
if (dir.exists(user_library)) {
  .libPaths(c(user_library, .libPaths()))
}
library(data.table)
source(file.path(root, "R/entrenamiento/com_zl.R"))
predictions <- data.table(split = "prueba", target = rep(0:1, each = 50000L))
predictions[, pred_prob := as.numeric(target)]
stopifnot(rf_training_metrics(predictions)$auc == 1)
predictions[, pred_prob := 1 - target]
stopifnot(rf_training_metrics(predictions)$auc == 0)
predictions[, pred_prob := 0.5]
stopifnot(rf_training_metrics(predictions)$auc == 0.5)
predictions[, target := 0L]
stopifnot(is.na(rf_training_metrics(predictions)$auc))
cat("R06_METRICS_LARGE_COUNTS_OK: perfecto, invertido, empates y clase unica\n")
