# Construye controles y vistas del modulo COM de muestra.  Entrada: identificador
# Shiny. Salida: interfaz con namespace propio.
rf_com_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_sidebar(sidebar = bslib::sidebar(shiny::selectInput(ns("strategy"), "Selección COM",
    c(`Umbral de score` = "umbral", `Porcentaje de la muestra` = "porcentaje_global",
      `Cantidad fija` = "fijo_global")), shiny::conditionalPanel(sprintf("input['%s'] == 'umbral'",
    ns("strategy")), shiny::sliderInput(ns("threshold"), "Score mínimo", 0, 1, 0.9,
    0.01)), shiny::conditionalPanel(sprintf("input['%s'] == 'porcentaje_global'", ns("strategy")),
    shiny::sliderInput(ns("percent"), "Porcentaje", 1, 100, 10, 1)), shiny::conditionalPanel(sprintf("input['%s'] == 'fijo_global'",
    ns("strategy")), shiny::numericInput(ns("count"), "Cantidad", 10, min = 0, step = 1)),
    shiny::textOutput(ns("summary")), shiny::p("Muestra retrospectiva: 50 primeros clusters COM del día indicado. Los porcentajes de selección se aplican a esta muestra."),
    shiny::p("Zona Limpia, pronóstico agregado, cupos barriales e histórico: pendientes de próximos componentes.")),
    bslib::navset_card_tab(bslib::nav_panel("Mapa", leaflet::leafletOutput(ns("map"),
      height = "560px")), bslib::nav_panel("Lista", DT::DTOutput(ns("table"))), bslib::nav_panel("Scores",
      shiny::plotOutput(ns("scores"), height = "360px"))))
}

# Sincroniza seleccion, mapa, lista e histograma del producto preparado.  Entradas:
# identificador y tabla COM. Salida: reactivo de seleccion; no ejecuta inferencia.
rf_com_server <- function(id, data) {
  shiny::moduleServer(id, function(input, output, session) {
    selected <- shiny::reactive({
      shiny::req(input$strategy)
      value <- switch(input$strategy, umbral = input$threshold, porcentaje_global = input$percent,
        fijo_global = input$count)
      shiny::req(!is.null(value))
      rf_select_com(data, input$strategy, value)
    })
    output$summary <- shiny::renderText(paste(format(data$dia_objetivo[[1]], "%d/%m/%Y"),
      ":", nrow(selected()), "de", nrow(data), "clusters seleccionados"))
    output$map <- leaflet::renderLeaflet({
      leaflet::addTiles(leaflet::setView(leaflet::leaflet(), mean(data$lng), mean(data$lat),
        12))
    })
    shiny::observe({
      s <- selected()
      map <- leaflet::clearMarkers(leaflet::leafletProxy("map", session = session))
      if (nrow(s))
        leaflet::addCircleMarkers(map, lng = s$lng, lat = s$lat, layerId = s$cluster_id,
          radius = 7, color = "#087f8c", fillOpacity = 0.8, label = paste(s$cluster_id,
          format(round(s$pred_prob, 4))))
    })
    output$table <- DT::renderDT({
      s <- selected()
      DT::datatable(s[c("cluster_id", "barrio", "pred_prob", "ranking_dia", "n_contenedores_activos",
        "estado_observacion")], rownames = FALSE, options = list(pageLength = 10),
        colnames = c("Cluster", "Barrio", "Score COM", "Ranking", "Contenedores",
          "Estado observado"))
    })
    output$scores <- shiny::renderPlot({
      graphics::hist(data$pred_prob, breaks = 15, col = "#087f8c", border = "white",
        main = "Scores COM de la muestra", xlab = "Score", ylab = "Clusters")
      if (identical(input$strategy, "umbral"))
        graphics::abline(v = input$threshold, col = "#c44601", lwd = 2)
    })
    list(selected = selected)
  })
}
