path_qmd <- "documentacion/informe_preliminar_validacion_modelos_2026.qmd"
path_html <- "documentacion/informe_preliminar_validacion_modelos_2026.html"
path_figuras <- "documentacion/informe_preliminar_validacion_modelos_2026_files/figure-html"

stopifnot(file.exists(path_qmd), file.exists(path_html), dir.exists(path_figuras))

qmd <- paste(readLines(path_qmd, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
html <- paste(readLines(path_html, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

stopifnot(
  grepl("dia <= as.Date\\(\"2026-06-30\"\\)", qmd),
  !grepl("predicciones[^\n]*(test|prueba)", qmd, ignore.case = TRUE),
  !grepl("metricas[^\n]*(test|prueba)", qmd, ignore.case = TRUE),
  grepl("Test reservado", html, fixed = TRUE),
  grepl("Resultados no mostrados", qmd, fixed = TRUE),
  grepl("0,7752", html, fixed = TRUE),
  grepl("149,70", html, fixed = TRUE),
  grepl("187,85", html, fixed = TRUE),
  grepl("q7 sola", html, fixed = TRUE),
  grepl("Cambio cuadr", html, fixed = TRUE),
  grepl("185,49", html, fixed = TRUE),
  grepl("Bootstrap del candidato cuadr", html, fixed = TRUE),
  grepl("50/50", html, fixed = TRUE),
  grepl("0,6107", html, fixed = TRUE),
  grepl("0,6263", html, fixed = TRUE),
  grepl("Municipio B", html, fixed = TRUE)
)

figuras_esperadas <- c(
  "auc-com-mensual-1.png",
  "lift-com-1.png",
  "serie-completa-splits-1.png",
  "validacion-pronostico-1.png",
  "coeficientes-inferencial-1.png",
  "auc-zl-mensual-1.png"
)
stopifnot(all(file.exists(file.path(path_figuras, figuras_esperadas))))

cat("VALIDACION_INFORME_PRELIMINAR_OK\n")
