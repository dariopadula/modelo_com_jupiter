setwd("..")
source("app.R", local = .GlobalEnv)

shiny::testServer(
  dia_zl_server,
  args = list(
    historia = historia_zl,
    centroides = datos_app$centroides,
    version_cluster = datos_app$version_cluster
  ),
  {
    session$setInputs(
      dia = tail(historia_zl$dias, 1),
      `seleccion-estrategia` = "porcentaje_global",
      `seleccion-porcentaje` = 10,
      `seleccion-cantidad` = 500,
      `seleccion-cantidad_barrio` = 10,
      `seleccion-umbral` = 0.5
    )
    session$flushReact()

    dt <- dia()
    pts <- puntos()
    tabla <- metricas()
    categorias <- c(
      "Seleccionado sin visita", "Seleccionado y visitado sin problema",
      "Seleccionado, visitado y con problema",
      "No seleccionado y visitado sin problema",
      "No seleccionado, visitado y con problema"
    )
    s <- seleccion$seleccion()
    stopifnot(
      nrow(dt) == data.table::uniqueN(dt$cluster_id),
      identical(sort(unique(pts$categoria)), sort(categorias)),
      nrow(pts) == data.table::uniqueN(c(
        s$cluster_id, dt[hay_zl_visita_efectiva == 1L]$cluster_id
      )),
      nrow(tabla) == 5L,
      sum(pts$categoria == "Seleccionado y visitado sin problema") ==
        sum(s$hay_zl_visita_efectiva == 1L & s$problema_zl_observado == 0L),
      sum(pts$categoria == "Seleccionado, visitado y con problema") ==
        sum(s$hay_zl_visita_efectiva == 1L & s$problema_zl_observado == 1L),
      sum(pts$categoria == "No seleccionado y visitado sin problema") ==
        sum(dt$hay_zl_visita_efectiva == 1L & dt$problema_zl_observado == 0L &
          !dt$cluster_id %in% s$cluster_id),
      sum(pts$categoria == "No seleccionado, visitado y con problema") ==
        sum(dt$hay_zl_visita_efectiva == 1L & dt$problema_zl_observado == 1L &
          !dt$cluster_id %in% s$cluster_id)
    )

    for (metodo in c(
      "porcentaje_global", "fijo_global", "umbral",
      "porcentaje_barrio", "fijo_barrio"
    )) {
      session$setInputs(`seleccion-estrategia` = metodo)
      session$flushReact()
      activa <- metricas()[activa == "Activa"]
      s <- seleccion$seleccion()
      s_visitada <- s[hay_zl_visita_efectiva == 1L]
      stopifnot(
        nrow(activa) == 1L,
        activa$seleccionados == nrow(s),
        activa$seleccionados_visitados == nrow(s_visitada),
        activa$seleccionados_sin_visita == nrow(s) - nrow(s_visitada),
        activa$problemas_capturados == sum(s_visitada$problema_zl_observado == 1L)
      )
    }

    resumen <- output$resumen
    visitados <- dt[hay_zl_visita_efectiva == 1L]
    pct_problemas <- mean(visitados$problema_zl_observado == 1L)
    pct_txt <- scales::percent(pct_problemas, accuracy = 0.1, decimal.mark = ",")
    stopifnot(
      grepl("evaluados", resumen), grepl("seleccionados", resumen),
      grepl("visitados", resumen), grepl("sin problema", resumen),
      grepl("visitados no seleccionados", resumen),
      grepl("con problema", resumen), grepl(pct_txt, resumen, fixed = TRUE)
    )
    invisible(output$metricas)
    invisible(output$mapa)
  }
)

cat("DIA_ZL_OK\n")
