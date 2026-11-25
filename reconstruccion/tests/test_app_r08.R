# Prueba contratos de publicacion, arranque, seleccion y evaluacion de R08.
arguments <- commandArgs(trailingOnly = FALSE)
script_path <- sub("^--file=", "", grep("^--file=", arguments, value = TRUE)[[1L]])
root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)
publication <- normalizePath(
  file.path(root, "runtime/r08_app/publicacion_piloto"),
  winslash = "/",
  mustWork = TRUE
)
Sys.setenv(RF_APP_PUBLICATION = publication)
setwd(file.path(root, "app"))
source("app.R", local = .GlobalEnv, encoding = "UTF-8")

expect_error <- function(expression) {
  result <- try(force(expression), silent = TRUE)
  stopifnot(inherits(result, "try-error"))
}

# El constructor produce una publicacion nueva y preserva claves y valores de entrada.
source(file.path(root, "R/publicacion/productos_app.R"), encoding = "UTF-8")
package <- readRDS(file.path(root, "runtime/r08_app/insumos/entrada.rds"))
source_scores <- arrow::open_dataset(
  package$scores_path,
  partitioning = arrow::hive_partition(
    dia_objetivo = arrow::date32(),
    modelo_id = arrow::utf8()
  )
) |>
  dplyr::collect() |>
  as.data.frame() |>
  data.table::as.data.table()
master <- data.table::as.data.table(as.data.frame(package$master))
source_day <- source_scores[dia_objetivo == as.Date("2026-03-31")]
stopifnot(isTRUE(rf_validate_app_day(source_day, master)))

# Reproduce el indice vacio heredado que descartaba todas las filas de COM.
stale_index_day <- data.table::copy(source_day)
stale_index <- integer()
attr(stale_index, "__modelo_id") <- integer()
data.table::setattr(stale_index_day, "index", stale_index)
stopifnot(isTRUE(rf_validate_app_day(stale_index_day, master)))
stopifnot(identical(attr(stale_index_day, "index"), stale_index))

invalid_score <- data.table::copy(source_day)
invalid_score[1L, pred_prob := 1.1]
expect_error(rf_validate_app_day(invalid_score, master))

duplicate_rank <- data.table::copy(source_day)
duplicate_rank[2L, ranking_dia := duplicate_rank$ranking_dia[1L]]
expect_error(rf_validate_app_day(duplicate_rank, master))

invalid_unvisited_target <- data.table::copy(source_day)
unvisited_row <- which(
  invalid_unvisited_target$modelo_id == "zl_problema" &
    invalid_unvisited_target$hay_zl_visita_efectiva != 1L
)[1L]
stopifnot(!is.na(unvisited_row))
invalid_unvisited_target[unvisited_row, problema_zl_observado := 0L]
expect_error(rf_validate_app_day(invalid_unvisited_target, master))

temporary_root <- tempfile("r08_products_test_")
dir.create(temporary_root)
temporary_publication <- file.path(temporary_root, "publicacion")
manifest <- rf_build_app_products(package, temporary_publication)
stopifnot(
  identical(manifest$status, "ready"),
  identical(manifest$dates, c("2026-03-31", "2026-05-24")),
  manifest$detail_rows == nrow(source_scores),
  manifest$operational_day == "2026-05-24"
)

published_scores <- arrow::open_dataset(
  file.path(temporary_publication, "historico/detalle_cluster_dia"),
  partitioning = arrow::hive_partition(
    dia_objetivo = arrow::date32(),
    modelo_id = arrow::utf8()
  )
) |>
  dplyr::collect() |>
  as.data.frame() |>
  data.table::as.data.table()
comparison_columns <- c(
  "cluster_id", "dia_objetivo", "modelo_id", "pred_prob", "ranking_dia",
  "percentil_riesgo", "estado_prediccion", "estado_periodo_app",
  "estado_observacion", "tuvo_reclamo_observado", "problema_zl_observado"
)
data.table::setorder(source_scores, dia_objetivo, modelo_id, cluster_id)
data.table::setorder(published_scores, dia_objetivo, modelo_id, cluster_id)
stopifnot(isTRUE(all.equal(
  source_scores[, ..comparison_columns],
  published_scores[, ..comparison_columns],
  check.attributes = FALSE
)))
expect_error(rf_build_app_products(package, temporary_publication))
cat("R08_PRODUCTS_ROUNDTRIP_OK: rows=", nrow(published_scores), "\n", sep = "")
unlink(temporary_root, recursive = TRUE)

# La app consume ambas familias y mantiene separadas sus reglas de seleccion.
shiny::testServer(server, {
  session$setInputs(
    `seleccion_com-estrategia` = "modelo_global",
    `seleccion_com-porcentaje` = 10,
    `seleccion_com-cantidad` = 500,
    `seleccion_com-cantidad_barrio` = 10,
    `seleccion_com-umbral` = 0.5,
    `seleccion_zl-estrategia` = "porcentaje_global",
    `seleccion_zl-porcentaje` = 10,
    `seleccion_zl-cantidad` = 500,
    `seleccion_zl-cantidad_barrio` = 10,
    `seleccion_zl-umbral` = 0.5
  )
  session$flushReact()

  stopifnot(
    nrow(com_dia()) > 0L,
    nrow(zl_dia()) > 0L,
    nrow(seleccion_com$seleccion()) > 0L,
    nrow(seleccion_zl$seleccion()) > 0L,
    nrow(agregado_dia()) == 1L,
    nrow(agregado_barrio_dia()) > 0L
  )

  expected_capacity <- round(agregado_dia()$predicho[[1L]])
  stopifnot(nrow(seleccion_com$seleccion()) == expected_capacity)

  session$setInputs(`seleccion_com-estrategia` = "umbral", `seleccion_com-umbral` = 0.35)
  session$flushReact()
  stopifnot(all(seleccion_com$seleccion()$pred_prob >= 0.35))
  invisible(output$actualizacion)
})
cat("R08_OPERATION_SERVER_OK\n")

# Las vistas historicas exponen ocho estrategias COM y cinco categorias ZL.
shiny::testServer(
  dia_com_server,
  args = list(
    historia = historia_com,
    centroides = datos_app$centroides,
    version_cluster = datos_app$version_cluster
  ),
  {
    session$setInputs(
      dia = historia_com$dias[[1L]],
      tamano = "1000",
      `seleccion-estrategia` = "modelo_global",
      `seleccion-umbral` = 0.5,
      `seleccion-porcentaje` = 10,
      `seleccion-cantidad` = 500,
      `seleccion-cantidad_barrio` = 10
    )
    stopifnot(nrow(dia()) > 0L, nrow(metricas()) == 8L)
    output$metricas
  }
)
cat("R08_COM_HISTORY_SERVER_OK\n")

shiny::testServer(
  dia_zl_server,
  args = list(
    historia = historia_zl,
    centroides = datos_app$centroides,
    version_cluster = datos_app$version_cluster
  ),
  {
    session$setInputs(
      dia = historia_zl$dias[[1L]],
      `seleccion-estrategia` = "porcentaje_global",
      `seleccion-porcentaje` = 10,
      `seleccion-cantidad` = 500,
      `seleccion-cantidad_barrio` = 10,
      `seleccion-umbral` = 0.5
    )
    session$flushReact()
    stopifnot(
      nrow(dia()) > 0L,
      nrow(metricas()) == 5L,
      all(is.na(dia()[hay_zl_visita_efectiva != 1L, problema_zl_observado]))
    )
    output$metricas
  }
)
cat("R08_ZL_HISTORY_SERVER_OK\n")

shiny::testServer(evolucion_server, args = list(serie = serie_evolucion), {
  dates <- range(serie_evolucion$dia_objetivo)
  session$setInputs(periodo = as.character(dates))
  session$flushReact()
  selected <- periodo()
  metrics <- metricas_evolucion(selected)
  stopifnot(
    nrow(selected) == nrow(serie_evolucion),
    length(metrics) == 4L,
    is.finite(metrics[["rmse"]]),
    is.finite(metrics[["mae"]])
  )
  invisible(output$serie)
  invisible(output$comparacion)
})
cat("R08_EVOLUTION_SERVER_OK\n")

ui_html <- htmltools::renderTags(ui)$html
ui_source <- paste(readLines("interfaz.R", warn = FALSE), collapse = "\n")
stopifnot(
  identical(.rf_publication$status, "ready"),
  identical(as.character(dia_operativo), "2026-05-24"),
  !grepl("dia_operativo", ui_source, fixed = TRUE),
  length(historia_com$dias) > 0L,
  length(historia_zl$dias) > 0L,
  nrow(serie_evolucion) > 0L,
  grepl("Mapa", ui_html, fixed = TRUE),
  grepl("Scores y umbrales", ui_html, fixed = TRUE),
  grepl("Clusters seleccionados", ui_html, fixed = TRUE)
)
cat("R08_APP_CONTRACTS_OK\n")

# Reproduce la carga de app.R que usa Shiny con su entorno aislado de ejecucion.
options(shiny.autoload.r = FALSE)
app_env <- new.env(parent = globalenv())
source("app.R", local = app_env, encoding = "UTF-8")
isolated_ui <- get("ui", envir = app_env)
rm(app_env)
invisible(gc())
isolated_ui_html <- htmltools::renderTags(isolated_ui)$html
stopifnot(grepl("24/05/2026", isolated_ui_html, fixed = TRUE))

stopifnot(!file.exists("server.R"), !file.exists("ui.R"))
app <- shiny::shinyAppDir(normalizePath(".", winslash = "/"))
server_source <- app$serverFuncSource()
stopifnot(is.function(server_source))
response <- app$httpHandler(list(
  REQUEST_METHOD = "GET", PATH_INFO = "/", QUERY_STRING = "",
  SCRIPT_NAME = "", HTTP_ACCEPT = "text/html"
))
stopifnot(response$status == 200L, grepl("24/05/2026", response$body, fixed = TRUE))
cat("R08_SHINY_APPDIR_UI_BOOT_OK\n")
