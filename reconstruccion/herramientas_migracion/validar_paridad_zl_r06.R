# Compara los scores del adaptador R06 con la muestra congelada R01.
# Entrada: artefactos runtime/r06_zl; salida: resumen y error ante desvio.
# Diagnostico historico conservado; desde 2026-10-22 no es el criterio de cierre R06.
# La aceptacion de migracion usa comparar_inferencia_zl_r06.R con insumos iguales.

script_arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", script_arguments, value = TRUE)[[1L]])
reconstruction_root <- normalizePath(file.path(dirname(script_path), ".."),
  winslash = "/", mustWork = TRUE)
library_version <- paste0(R.version$major, ".", sub("\\..*$", "", R.version$minor))
user_library <- Sys.getenv("RF_R_LIBRARY", unset = Sys.getenv("R_LIBS_USER", unset = ""))
if ((!nzchar(user_library) || !dir.exists(user_library)) && identical(Sys.info()[["sysname"]], "Windows") &&
    nzchar(Sys.getenv("USERPROFILE"))) {
  user_library <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "R", "win-library", library_version)
}
if (nzchar(user_library) && dir.exists(user_library)) {
  .libPaths(c(user_library, .libPaths()))
}

source(file.path(reconstruction_root, "R/features/zl_receta.R"))
source(file.path(reconstruction_root, "R/modelos/zl_xgboost.R"))
model <- readRDS(file.path(reconstruction_root, "runtime/r06_zl/modelo_zl.rds"))
sample <- readRDS(file.path(reconstruction_root, "runtime/r06_zl/muestra_zl.rds"))
scored <- rf_score_zl(sample$data, model)
reference <- sample$data[, .(cluster_id, pred_prob)]
comparison <- merge(scored[, .(cluster_id, pred_prob)], reference,
  by = "cluster_id", suffixes = c("_nuevo", "_referencia"))
if (nrow(comparison) != nrow(reference)) {
  stop("La cantidad de scores no coincide con la muestra de referencia")
}

comparison[, diferencia_absoluta := abs(pred_prob_nuevo - pred_prob_referencia)]
max_difference <- max(comparison$diferencia_absoluta)
cat("filas=", nrow(comparison), " diferencia_absoluta_maxima=",
  format(max_difference, scientific = TRUE), "\n", sep = "")
if (max_difference > 1e-6) {
  print(comparison[diferencia_absoluta > 1e-6,
    .(cluster_id, pred_prob_nuevo, pred_prob_referencia, diferencia_absoluta)])
  stop("La paridad numérica ZL supera la tolerancia de 1e-6")
}

cat("R06_ZL_NUMERIC_EQUIVALENCE_OK\n")
