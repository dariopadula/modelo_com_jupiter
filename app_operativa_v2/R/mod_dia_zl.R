preparar_historia_zl <- function() {
  ds <- abrir_detalle_com()
  fechas <- ds |>
    dplyr::filter(
      modelo_id == "zl_problema",
      estado_periodo_app == "historico_cerrado",
      hay_zl_visita_efectiva == 1L
    ) |>
    dplyr::distinct(dia_objetivo) |>
    dplyr::collect()
  list(ds = ds, dias = sort(as.character(fechas$dia_objetivo)))
}

clasificar_puntos_zl <- function(dia, seleccionados) {
  dt <- data.table::copy(dia)
  dt[, seleccionado := cluster_id %in% seleccionados$cluster_id]
  dt[, categoria := data.table::fcase(
    seleccionado & hay_zl_visita_efectiva == 1L & problema_zl_observado == 1L,
      "Seleccionado, visitado y con problema",
    seleccionado & hay_zl_visita_efectiva == 1L,
      "Seleccionado y visitado sin problema",
    seleccionado, "Seleccionado sin visita",
    hay_zl_visita_efectiva == 1L & problema_zl_observado == 1L,
      "No seleccionado, visitado y con problema",
    hay_zl_visita_efectiva == 1L,
      "No seleccionado y visitado sin problema",
    default = NA_character_
  )]
  dt[!is.na(categoria)]
}

dia_zl_ui <- function(id, historia) {
  ns <- NS(id)
  layout_sidebar(
    sidebar = sidebar(
      width = 265,
      selectInput(
        ns("dia"), "D\u00eda observado cerrado",
        choices = setNames(historia$dias, format(as.Date(historia$dias), "%d/%m/%Y")),
        selected = tail(historia$dias, 1)
      ),
      seleccion_ui(ns("seleccion"), "zl"),
      p("El mapa muestra el resultado observado dentro de la selecci\u00f3n del modelo. Un cluster sin visita no se considera limpio.")
    ),
    div(
      class = "day-zl-page",
      textOutput(ns("resumen")),
      card(
        card_header("Resultado de los puntos seleccionados por el modelo ZL"),
        leafletOutput(ns("mapa"), height = "68vh")
      ),
      card(
        card_header("Comparaci\u00f3n de estrategias de selecci\u00f3n"),
        p("Precisi\u00f3n y lift se calculan solamente entre seleccionados con visita efectiva. Cobertura compara los problemas capturados con todos los problemas observados ese d\u00eda."),
        DTOutput(ns("metricas"))
      )
    )
  )
}

dia_zl_server <- function(id, historia, centroides, version_cluster) {
  moduleServer(id, function(input, output, session) {
    dia <- reactive({
      req(input$dia)
      fecha <- as.Date(input$dia)
      dt <- historia$ds |>
        dplyr::filter(dia_objetivo == !!fecha, modelo_id == "zl_problema") |>
        dplyr::collect() |>
        data.table::as.data.table()
      validate(
        need(nrow(dt) > 0, "Sin datos para este d\u00eda."),
        need(all(dt$estado_periodo_app == "historico_cerrado"), "El d\u00eda todav\u00eda est\u00e1 pendiente de validaci\u00f3n."),
        need(any(dt$hay_zl_visita_efectiva == 1L), "El d\u00eda no tiene visitas efectivas de Zona Limpia."),
        need(all(dt$estado_observacion_zl %in% c("observado", "no_observado")), "Los estados observados ZL no son v\u00e1lidos."),
        need(all(dt$version_cluster == version_cluster), "La versi\u00f3n territorial no coincide."),
        need(!anyDuplicated(dt$cluster_id), "Clusters duplicados."),
        need(all(dt$cluster_id %in% centroides$cluster_id), "Faltan coordenadas: no se comparar\u00e1 un universo incompleto.")
      )
      merge(dt, centroides, by = "cluster_id", all.x = TRUE)
    })

    vacio <- reactive(data.table::data.table())
    seleccion <- seleccion_server("seleccion", "zl", dia, vacio, vacio)
    puntos <- reactive(clasificar_puntos_zl(dia(), seleccion$seleccion()))

    metricas <- reactive({
      dt <- dia()
      visitados <- dt[hay_zl_visita_efectiva == 1L]
      positivos <- sum(visitados$problema_zl_observado == 1L)
      prevalencia <- if (nrow(visitados)) positivos / nrow(visitados) else NA_real_
      selecciones <- seleccion$comparar()
      etiquetas <- c(
        porcentaje_global = "Porcentaje global",
        fijo_global = "Cantidad global fija",
        umbral = "Umbral de score",
        porcentaje_barrio = "Porcentaje dentro de cada barrio",
        fijo_barrio = "Cantidad fija por barrio"
      )
      data.table::rbindlist(lapply(names(selecciones), function(metodo) {
        s <- selecciones[[metodo]]
        s_visitada <- s[hay_zl_visita_efectiva == 1L]
        capturados <- sum(s_visitada$problema_zl_observado == 1L)
        precision <- if (nrow(s_visitada)) capturados / nrow(s_visitada) else NA_real_
        data.table::data.table(
          activa = if (metodo == seleccion$estrategia()) "Activa" else "",
          estrategia = etiquetas[[metodo]],
          parametro = seleccion$parametros()[[metodo]],
          seleccionados = nrow(s),
          seleccionados_sin_visita = nrow(s) - nrow(s_visitada),
          seleccionados_visitados = nrow(s_visitada),
          problemas_capturados = capturados,
          precision = precision,
          cobertura = if (positivos > 0) capturados / positivos else NA_real_,
          lift = if (is.finite(prevalencia) && prevalencia > 0) precision / prevalencia else NA_real_
        )
      }))
    })

    output$resumen <- renderText({
      dt <- dia()
      s <- seleccion$seleccion()
      visitados <- dt[hay_zl_visita_efectiva == 1L]
      problemas <- sum(visitados$problema_zl_observado == 1L)
      sin_problema <- nrow(visitados) - problemas
      visitados_no_seleccionados <- sum(!visitados$cluster_id %in% s$cluster_id)
      pct_problemas <- if (nrow(visitados)) problemas / nrow(visitados) else NA_real_
      pct_problemas_txt <- if (is.finite(pct_problemas)) {
        scales::percent(pct_problemas, accuracy = 0.1, decimal.mark = ",")
      } else {
        "No calculable"
      }
      paste0(
        format(nrow(dt), big.mark = ".", decimal.mark = ","), " evaluados \u00b7 ",
        format(nrow(s), big.mark = ".", decimal.mark = ","), " seleccionados \u00b7 ",
        format(nrow(visitados), big.mark = ".", decimal.mark = ","), " visitados \u00b7 ",
        format(visitados_no_seleccionados, big.mark = ".", decimal.mark = ","),
          " visitados no seleccionados \u00b7 ",
        format(sin_problema, big.mark = ".", decimal.mark = ","), " sin problema \u00b7 ",
        format(problemas, big.mark = ".", decimal.mark = ","), " con problema (",
        pct_problemas_txt, " de los visitados)"
      )
    })

    output$metricas <- renderDT({
      datatable(
        metricas(), rownames = FALSE,
        colnames = c(
          "", "Estrategia", "Par\u00e1metro", "Seleccionados",
          "Sin visita", "Visitados", "Problemas capturados",
          "Precisi\u00f3n", "Cobertura", "Lift"
        ),
        options = list(dom = "t", ordering = TRUE, pageLength = 5, scrollX = TRUE)
      ) |>
        formatPercentage(c("precision", "cobertura"), digits = 1) |>
        formatRound("lift", digits = 2)
    })

    output$mapa <- renderLeaflet({
      leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
        addProviderTiles(providers$CartoDB.Positron) |>
        setView(-56.16, -34.86, 11)
    })

    observe({
      s <- seleccion$seleccion()
      dt <- dia()
      visitados <- dt[hay_zl_visita_efectiva == 1L]
      visitados[, seleccionado_mapa := cluster_id %in% s$cluster_id]
      visitados_seleccionados <- visitados[seleccionado_mapa == TRUE]
      visitados_no_seleccionados <- visitados[seleccionado_mapa == FALSE]
      problemas <- visitados[problema_zl_observado == 1L]
      proxy <- leafletProxy("mapa", session = session) |>
        clearGroup("seleccion") |>
        clearGroup("visitas_seleccionadas") |>
        clearGroup("visitas_no_seleccionadas") |>
        clearGroup("problemas") |>
        clearControls()
      if (nrow(s)) {
        proxy <- proxy |> addCircleMarkers(
          data = s, lng = ~lng, lat = ~lat, group = "seleccion",
          radius = 8, stroke = TRUE, weight = 2, color = "#5f6368",
          opacity = 0.8, dashArray = "3 3", fill = FALSE,
          label = ~paste0("Cluster ", cluster_id, " - score ",
            scales::percent(pred_prob, accuracy = 0.1))
        )
      }
      if (nrow(visitados_seleccionados)) {
        proxy <- proxy |> addCircleMarkers(
          data = visitados_seleccionados, lng = ~lng, lat = ~lat,
          group = "visitas_seleccionadas",
          radius = 4, stroke = TRUE, weight = 2.5, color = "#138a4b",
          opacity = 1, fill = TRUE, fillColor = "#d9f2e3", fillOpacity = 0.55,
          label = ~paste("Cluster", cluster_id, "- seleccionado y visitado",
            ifelse(problema_zl_observado == 1L, "con problema", "sin problema"))
        )
      }
      if (nrow(visitados_no_seleccionados)) {
        proxy <- proxy |> addCircleMarkers(
          data = visitados_no_seleccionados, lng = ~lng, lat = ~lat,
          group = "visitas_no_seleccionadas",
          radius = 4, stroke = TRUE, weight = 2.5, color = "#2869b2",
          opacity = 1, fill = TRUE, fillColor = "#dceafb", fillOpacity = 0.55,
          label = ~paste("Cluster", cluster_id, "- no seleccionado y visitado",
            ifelse(problema_zl_observado == 1L, "con problema", "sin problema"))
        )
      }
      if (nrow(problemas)) {
        proxy <- proxy |> addCircleMarkers(
          data = problemas, lng = ~lng, lat = ~lat, group = "problemas",
          radius = 2.3, stroke = FALSE, fillColor = "#d14900", fillOpacity = 1,
          label = ~paste("Cluster", cluster_id, "- visitado con problema")
        )
      }
      proxy |> addControl(
        html = htmltools::HTML(paste0(
          '<div style="padding:8px 10px;background:rgba(255,255,255,.96);',
          'border:1px solid #cfd6dc;border-radius:5px;box-shadow:0 1px 4px rgba(0,0,0,.16);',
          'font-size:12px;line-height:24px;color:#17212b">',
          '<div><svg width="18" height="18" style="vertical-align:middle;margin-right:6px">',
          '<circle cx="9" cy="9" r="7" fill="none" stroke="#5f6368" stroke-width="2" stroke-dasharray="3 2"/></svg>Seleccionado sin visita</div>',
          '<div><svg width="18" height="18" style="vertical-align:middle;margin-right:6px">',
          '<circle cx="9" cy="9" r="7" fill="none" stroke="#5f6368" stroke-width="2" stroke-dasharray="3 2"/>',
          '<circle cx="9" cy="9" r="4" fill="#d9f2e3" fill-opacity=".55" stroke="#138a4b" stroke-width="2"/></svg>Seleccionado y visitado sin problema</div>',
          '<div><svg width="18" height="18" style="vertical-align:middle;margin-right:6px">',
          '<circle cx="9" cy="9" r="7" fill="none" stroke="#5f6368" stroke-width="2" stroke-dasharray="3 2"/>',
          '<circle cx="9" cy="9" r="4" fill="#d9f2e3" fill-opacity=".55" stroke="#138a4b" stroke-width="2"/>',
          '<circle cx="9" cy="9" r="2.5" fill="#d14900"/></svg>Seleccionado, visitado y con problema</div>',
          '<div><svg width="18" height="18" style="vertical-align:middle;margin-right:6px">',
          '<circle cx="9" cy="9" r="4" fill="#dceafb" fill-opacity=".55" stroke="#2869b2" stroke-width="2"/></svg>No seleccionado, visitado sin problema</div>',
          '<div><svg width="18" height="18" style="vertical-align:middle;margin-right:6px">',
          '<circle cx="9" cy="9" r="4" fill="#dceafb" fill-opacity=".55" stroke="#2869b2" stroke-width="2"/>',
          '<circle cx="9" cy="9" r="2.5" fill="#d14900"/></svg>No seleccionado, visitado con problema</div>',
          '</div>'
        )),
        position = "bottomright"
      )
    })

    list(dia = dia, seleccion = seleccion, puntos = puntos, metricas = metricas)
  })
}
