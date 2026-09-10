setwd("..")
source("app.R", local = .GlobalEnv)
shiny::testServer(dia_com_server, args = list(historia = historia_com,
    centroides = datos_app$centroides, version_cluster = datos_app$version_cluster), {
  session$setInputs(dia = tail(historia_com$dias, 1), tamano = "1000",
    `seleccion-estrategia` = "modelo_global", `seleccion-umbral` = 0.5,
    `seleccion-porcentaje` = 10, `seleccion-cantidad` = 500, `seleccion-cantidad_barrio` = 10)
  h <- distribucion()
  stopifnot(abs(sum(h$pct_sel) - 100) < 1e-7, abs(sum(h$pct_obs) - 100) < 1e-7,
    sum(h$observados) == sum(dia()$tuvo_reclamo_observado),
    nrow(dia()) == data.table::uniqueN(dia()$cluster_id))
  resumen <- output$resumen
  estimado <- round(agregado()$predicho[[1]])
  stopifnot(grepl("evaluados", resumen), grepl("seleccionados", resumen),
    grepl("observados", resumen), grepl("estimados", resumen),
    grepl(format(estimado, big.mark = ".", decimal.mark = ","), resumen, fixed = TRUE))
  stopifnot(nrow(metricas()) == 8L)
  invisible(output$metricas)
  session$setInputs(puntos_seleccionados = TRUE, puntos_observados = TRUE)
  for (metodo in c("porcentaje_global", "fijo_global", "umbral", "porcentaje_barrio",
                    "fijo_barrio", "modelo_barrio", "capacidad_barrio")) {
    session$setInputs(`seleccion-estrategia` = metodo)
    h <- distribucion()
    stopifnot(sum(h$seleccionados) == nrow(seleccion$seleccion()))
    activa <- metricas()[activa == "Activa"]
    s <- seleccion$seleccion()
    stopifnot(nrow(activa) == 1L, activa$seleccionados == nrow(s),
      activa$observados_capturados == sum(s$tuvo_reclamo_observado == 1L))
  }
  session$setInputs(`seleccion-estrategia` = "fijo_global", `seleccion-cantidad` = 0)
  stopifnot(all(is.na(distribucion()$pct_sel)))
  stopifnot(is.na(metricas()[activa == "Activa"]$precision))
})
cat("DIA_COM_OK\n")
