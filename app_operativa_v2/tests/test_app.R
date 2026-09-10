Sys.setenv(
  APP_DATA_PATH = normalizePath(
    "../data/operacional",
    winslash = "/",
    mustWork = TRUE
  )
)
Sys.setenv(
  APP_HISTORICO_PATH = normalizePath(
    "../data/historico",
    winslash = "/",
    mustWork = TRUE
  ),
  APP_CLUSTER_PATH = normalizePath(
    "../data/referencia/maestro_clusters",
    winslash = "/",
    mustWork = TRUE
  ),
  APP_BARRIOS_PATH = normalizePath(
    "../data/referencia/barrios_mvd_23_pg.gpkg",
    winslash = "/",
    mustWork = TRUE
  )
)

setwd("..")
source("app.R", local = .GlobalEnv)

shiny::testServer(server, {
  session$setInputs(
    `seleccion_com-estrategia` = "modelo_global",
    `seleccion_com-porcentaje` = 10,
    `seleccion_com-cantidad` = 500,
    `seleccion_com-cantidad_barrio` = 10,
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

  esperado <- round(agregado_dia()$predicho[[1]])
  stopifnot(nrow(seleccion_com$seleccion()) == esperado)

  session$setInputs(
    `seleccion_com-estrategia` = "umbral",
    `seleccion_com-umbral` = 0.35
  )
  session$flushReact()
  stopifnot(
    nrow(seleccion_com$seleccion()) > 0L,
    all(seleccion_com$seleccion()$pred_prob >= 0.35)
  )

  invisible(output$actualizacion)
})

cat("SESSION_OK\n")
