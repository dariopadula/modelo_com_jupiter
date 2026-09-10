mapa_operativo_ui <- function(id) {
  ns <- NS(id)
  div(
    class = "map-stage",
    leafletOutput(ns("mapa"), height = "76vh"),
    absolutePanel(
      class = "map-layer-control",
      top = 10,
      right = 10,
      checkboxGroupInput(
        ns("capas"),
        label = NULL,
        choices = c(
          "COM" = "COM",
          "Zona Limpia" = "Zona Limpia",
          "Estimacion barrial" = "Estimacion barrial"
        ),
        selected = c("COM", "Zona Limpia")
      )
    )
  )
}

mapa_operativo_server <- function(id, com, zl, barrios, pronostico_barrio_dia) {
  moduleServer(id, function(input, output, session) {
    output$mapa <- renderLeaflet({
      mapa <- leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
        addProviderTiles(providers$CartoDB.Positron) |>
        setView(lng = -56.16, lat = -34.86, zoom = 12)

      if (nrow(barrios)) {
        resumen <- pronostico_barrio_dia()[, .(
          cod_barrio_ine,
          estimado = predicho,
          n_clusters
        )]
        mapa_barrios <- merge(barrios, resumen, by = "cod_barrio_ine", all.x = TRUE)
        pal <- colorNumeric(
          c("#fff4dd", "#ef9b63", "#a8412d"),
          domain = mapa_barrios$estimado,
          na.color = "transparent"
        )
        mapa <- mapa |>
          addPolygons(
            data = mapa_barrios,
            group = "Estimacion barrial",
            color = "#7f858a",
            weight = 0.7,
            fillColor = ~pal(estimado),
            fillOpacity = 0.36,
            label = ~paste0(NOMBARRIOINE, ": ", round(estimado, 1), " esperados")
          ) |>
          hideGroup("Estimacion barrial")
      }

      dt_com <- com()
      if (nrow(dt_com)) {
        mapa <- mapa |> addCircleMarkers(
          data = dt_com,
          lng = ~lng,
          lat = ~lat,
          radius = 4.5,
          stroke = FALSE,
          fillColor = "#1769aa",
          fillOpacity = 0.82,
          group = "COM",
          label = ~paste0("COM · ", cluster_id, " · ", scales::percent(pred_prob, accuracy = 0.1)),
          popup = ~paste0(
            "<strong>Cluster ", cluster_id, "</strong><br>",
            "Barrio: ", barrio, "<br>",
            "Score COM: ", scales::percent(pred_prob, accuracy = 0.1), "<br>",
            "Ranking: ", ranking_dia
          )
        )
      }

      dt_zl <- zl()
      if (nrow(dt_zl)) {
        mapa <- mapa |> addCircleMarkers(
          data = dt_zl,
          lng = ~lng,
          lat = ~lat,
          radius = 7,
          color = "#d95f02",
          weight = 2,
          fill = FALSE,
          opacity = 0.92,
          group = "Zona Limpia",
          label = ~paste0("ZL · ", cluster_id, " · ", scales::percent(pred_prob, accuracy = 0.1)),
          popup = ~paste0(
            "<strong>Cluster ", cluster_id, "</strong><br>",
            "Barrio: ", barrio, "<br>",
            "Score ZL: ", scales::percent(pred_prob, accuracy = 0.1), "<br>",
            "Ranking: ", ranking_dia
          )
        )
      }

      mapa
    })

    observeEvent(input$capas, {
      proxy <- leafletProxy("mapa", session = session)
      for (grupo in c("COM", "Zona Limpia", "Estimacion barrial")) {
        if (grupo %in% input$capas) {
          proxy <- proxy |> showGroup(grupo)
        } else {
          proxy <- proxy |> hideGroup(grupo)
        }
      }
    }, ignoreInit = FALSE)
  })
}
