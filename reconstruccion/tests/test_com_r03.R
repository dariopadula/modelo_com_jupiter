all <- commandArgs(FALSE)
script <- sub("^--file=", "", grep("^--file=", all, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script), ".."), winslash = "/", mustWork = TRUE)
.libPaths(c("C:/Users/dario/AppData/Local/R/win-library/4.5", .libPaths()))
source(file.path(root, "R/features/com_receta.R"))
source(file.path(root, "R/modelos/com_logistico.R"))
source(file.path(root, "R/registro/contratos.R"))
source(file.path(root, "app/datos_com.R"))
source(file.path(root, "app/seleccion_com.R"))
source(file.path(root, "app/mod_com.R"))
path <- file.path(root, "runtime/r03_com")
entry <- readRDS(file.path(path, "entrada.rds"))
model <- readRDS(file.path(path, "modelo_com.rds"))
ref <- as.data.frame(readRDS(file.path(path, "referencia_predicciones.rds")))
pred <- rf_score_com(entry$history, model, entry$day, entry$universe_n)
ref <- ref[match(pred$cluster_id, ref$cluster_id), ]
stopifnot(max(abs(pred$pred_prob - ref$pred_prob)) <= 1e-10, identical(as.integer(pred$ranking_dia),
  as.integer(ref$ranking_dia)))
for (key in c("top_1", "top_5", "top_10", "top_20")) stopifnot(identical(pred[[key]], ref[[key]]))
product <- rf_read_com_product(root)
stopifnot(rf_prediction_contract(product), identical(product$cluster_id, pred$cluster_id),
  identical(product$estado_observacion, ref$estado_observacion), identical(product$estado_periodo_app,
    ref$estado_periodo_app), all(is.finite(product$lng)), all(is.finite(product$lat)))
for (strategy in c("umbral", "porcentaje_global", "fijo_global")) {
  value <- switch(strategy, umbral = 0.9, porcentaje_global = 10, fijo_global = 10)
  expected <- switch(strategy, umbral = ref[ref$pred_prob >= value, ], porcentaje_global = head(ref,
    ceiling(nrow(ref) * value/100)), fijo_global = head(ref, round(value)))
  stopifnot(identical(rf_select_com(product, strategy, value)$cluster_id, expected$cluster_id))
}
stopifnot(nrow(rf_select_com(product, "fijo_global", 0)) == 0L, nrow(rf_select_com(product,
  "umbral", 1)) == 0L)
tie <- product[1:3, ]
tie$pred_prob <- 0.5
stopifnot(identical(rf_select_com(tie[3:1, ], "fijo_global", 3)$cluster_id, tie$cluster_id))
bad <- entry$history
bad$version_cluster <- "otra"
stopifnot(inherits(try(rf_score_com(bad, model, entry$day, entry$universe_n), silent = TRUE),
  "try-error"))
shiny::testServer(rf_com_server, args = list(data = product), {
  session$setInputs(strategy = "umbral", threshold = 0.9)
  stopifnot(identical(selected()$cluster_id, product$cluster_id[product$pred_prob >= 0.9]))
  session$setInputs(strategy = "fijo_global", count = 10)
  stopifnot(nrow(selected()) == 10L)
  session$setInputs(strategy = "porcentaje_global", percent = 10)
  stopifnot(nrow(selected()) == 5L)
  stopifnot(!is.null(output$table), !is.null(output$map), !is.null(output$scores))
})
cat("R03_COM_OK: scores, ranking, seleccion, mapa, estados y servidor\n")
