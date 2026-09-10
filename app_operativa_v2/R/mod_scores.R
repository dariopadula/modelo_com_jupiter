scores_umbral_ui <- function(id) {
  ns <- NS(id)
  div(
    class = "scores-page",
    div(
      class = "scores-toolbar",
      selectInput(
        ns("modelo"),
        "Score a analizar",
        choices = c("COM" = "com", "Zona Limpia" = "zl"),
        selected = "com",
        width = "220px"
      ),
      div(class = "threshold-context", textOutput(ns("contexto"), inline = TRUE))
    ),
    layout_columns(
      card(
        class = "score-card",
        card_header("Distribucion de scores"),
        plotlyOutput(ns("histograma"), height = "61vh")
      ),
      card(
        class = "score-card",
        card_header("Clusters seleccionados segun el umbral"),
        plotlyOutput(ns("curva"), height = "61vh")
      ),
      col_widths = c(6, 6)
    )
  )
}

scores_umbral_server <- function(id,
                                 datos_com,
                                 datos_zl,
                                 umbral_com,
                                 umbral_zl,
                                 estrategia_com,
                                 estrategia_zl) {
  moduleServer(id, function(input, output, session) {
    datos_activos <- reactive({
      if (identical(input$modelo, "zl")) datos_zl() else datos_com()
    })
    umbral_activo <- reactive({
      if (identical(input$modelo, "zl")) umbral_zl() else umbral_com()
    })
    estrategia_activa <- reactive({
      if (identical(input$modelo, "zl")) estrategia_zl() else estrategia_com()
    })
    color_activo <- reactive(if (identical(input$modelo, "zl")) "#d95f02" else "#1769aa")

    output$contexto <- renderText({
      dt <- datos_activos()
      umbral <- umbral_activo()
      req(nrow(dt), is.finite(umbral))
      n <- sum(dt$pred_prob >= umbral, na.rm = TRUE)
      estado <- if (identical(estrategia_activa(), "umbral")) {
        "seleccion activa"
      } else {
        "referencia; la seleccion activa usa otro criterio"
      }
      paste0(
        "Umbral ", scales::percent(umbral, accuracy = 0.1),
        " - ", format(n, big.mark = ".", decimal.mark = ","),
        " clusters (", scales::percent(n / nrow(dt), accuracy = 0.1), ") - ",
        estado
      )
    })

    output$histograma <- renderPlotly({
      dt <- datos_activos()
      umbral <- umbral_activo()
      req(nrow(dt), is.finite(umbral))

      h <- hist(dt$pred_prob, breaks = 36, plot = FALSE)
      barras <- data.table::data.table(
        inicio = head(h$breaks, -1L),
        fin = tail(h$breaks, -1L),
        medio = h$mids,
        cantidad = h$counts
      )
      barras[, supera := medio >= umbral]
      ancho <- if (nrow(barras)) diff(h$breaks)[[1]] * 0.94 else 0.01

      plot_ly(
        barras,
        x = ~medio,
        y = ~cantidad,
        type = "bar",
        width = ancho,
        marker = list(color = ifelse(barras$supera, color_activo(), "#cfd6dc")),
        text = ~paste0(
          "Score: ", scales::percent(inicio, accuracy = 0.1),
          " a ", scales::percent(fin, accuracy = 0.1),
          "<br>Clusters: ", format(cantidad, big.mark = ".", decimal.mark = ",")
        ),
        hoverinfo = "text"
      ) |>
        layout(
          xaxis = list(title = "Score", tickformat = ".0%"),
          yaxis = list(title = "Cantidad de clusters"),
          margin = list(l = 65, r = 20, t = 20, b = 55),
          showlegend = FALSE,
          shapes = list(list(
            type = "line",
            x0 = umbral,
            x1 = umbral,
            y0 = 0,
            y1 = max(barras$cantidad) * 1.04,
            line = list(color = color_activo(), width = 2, dash = "dash")
          ))
        )
    })

    output$curva <- renderPlotly({
      dt <- datos_activos()
      umbral <- umbral_activo()
      req(nrow(dt), is.finite(umbral))

      limite <- max(dt$pred_prob, na.rm = TRUE)
      umbrales <- sort(unique(c(seq(0, limite, length.out = 120), umbral)))
      curva <- data.table::data.table(
        umbral = umbrales,
        clusters = vapply(
          umbrales,
          function(x) sum(dt$pred_prob >= x, na.rm = TRUE),
          integer(1)
        )
      )
      punto <- curva[which.min(abs(curva$umbral - umbral))]

      plot_ly(
        curva,
        x = ~umbral,
        y = ~clusters,
        type = "scatter",
        mode = "lines",
        line = list(color = color_activo(), width = 2.5),
        text = ~paste0(
          "Umbral: ", scales::percent(umbral, accuracy = 0.1),
          "<br>Seleccionados: ", format(clusters, big.mark = ".", decimal.mark = ",")
        ),
        hoverinfo = "text"
      ) |>
        add_markers(
          data = punto,
          x = ~umbral,
          y = ~clusters,
          marker = list(color = color_activo(), size = 10, line = list(color = "white", width = 2)),
          inherit = FALSE,
          text = ~paste0(
            "Umbral activo: ", scales::percent(umbral, accuracy = 0.1),
            "<br>Seleccionados: ", format(clusters, big.mark = ".", decimal.mark = ",")
          ),
          hoverinfo = "text",
          showlegend = FALSE
        ) |>
        layout(
          xaxis = list(title = "Umbral", tickformat = ".0%"),
          yaxis = list(title = "Clusters seleccionados", rangemode = "tozero"),
          margin = list(l = 70, r = 20, t = 20, b = 55),
          showlegend = FALSE
        )
    })
  })
}
