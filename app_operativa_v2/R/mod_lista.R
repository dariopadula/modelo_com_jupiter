lista_clusters_ui <- function(id) {
  ns <- NS(id)
  card(
    class = "list-card",
    card_header(
      div(
        class = "list-header",
        span("Clusters seleccionados"),
        selectInput(
          ns("filtro"),
          label = NULL,
          choices = c(
            "Todos" = "todos",
            "Solo COM" = "com",
            "Solo Zona Limpia" = "zl",
            "Coincidencias" = "coincidencias"
          ),
          selected = "todos",
          width = "210px"
        )
      )
    ),
    DTOutput(ns("tabla"))
  )
}

lista_clusters_server <- function(id, com, zl) {
  moduleServer(id, function(input, output, session) {
    tabla <- reactive({
      a <- com()[, .(
        cluster_id,
        barrio_com = barrio,
        score_com = pred_prob,
        ranking_com = ranking_dia,
        contenedores_com = n_contenedores_activos
      )]
      b <- zl()[, .(
        cluster_id,
        barrio_zl = barrio,
        score_zl = pred_prob,
        ranking_zl = ranking_dia,
        contenedores_zl = n_contenedores_activos
      )]
      dt <- merge(a, b, by = "cluster_id", all = TRUE)
      dt[, `:=`(
        COM = !is.na(score_com),
        `Zona Limpia` = !is.na(score_zl),
        Coincidencia = !is.na(score_com) & !is.na(score_zl),
        Barrio = data.table::fcoalesce(barrio_com, barrio_zl),
        Contenedores = data.table::fcoalesce(contenedores_com, contenedores_zl)
      )]

      if (input$filtro == "com") dt <- dt[COM == TRUE & `Zona Limpia` == FALSE]
      if (input$filtro == "zl") dt <- dt[COM == FALSE & `Zona Limpia` == TRUE]
      if (input$filtro == "coincidencias") dt <- dt[Coincidencia == TRUE]

      dt[, .(
        Cluster = cluster_id,
        Barrio,
        COM = ifelse(COM, "Si", ""),
        `Score COM` = score_com,
        `Zona Limpia` = ifelse(`Zona Limpia`, "Si", ""),
        `Score ZL` = score_zl,
        Coincidencia = ifelse(Coincidencia, "Si", ""),
        Contenedores
      )]
    })

    output$tabla <- renderDT({
      datatable(
        tabla(),
        rownames = FALSE,
        filter = "top",
        options = list(pageLength = 20, scrollX = TRUE, order = list(list(1, "asc")))
      ) |>
        formatPercentage(c("Score COM", "Score ZL"), digits = 1)
    })
  })
}
