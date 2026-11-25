resumen_operativo_ui <- function(id) {
  ns <- NS(id)
  tags$details(
    class = "day-summary-v2",
    tags$summary("Resumen del d\u00eda"),
    div(
      class = "summary-grid",
      div(class = "summary-card", span("Clusters evaluados"), strong(textOutput(ns("evaluados"), inline = TRUE))),
      div(class = "summary-card summary-com", span("Selecci\u00f3n COM"), strong(textOutput(ns("com"), inline = TRUE))),
      div(class = "summary-card summary-zl", span("Selecci\u00f3n ZL"), strong(textOutput(ns("zl"), inline = TRUE))),
      div(class = "summary-card", span("Coincidencias"), strong(textOutput(ns("coincidencias"), inline = TRUE))),
      div(class = "summary-card summary-expected", span("Clusters con reclamo esperados"), strong(textOutput(ns("esperados"), inline = TRUE)))
    )
  )
}

resumen_operativo_server <- function(id, evaluados, com, zl, pronostico_dia) {
  moduleServer(id, function(input, output, session) {
    formato <- function(x) format(x, big.mark = ".", decimal.mark = ",")
    output$evaluados <- renderText(formato(nrow(evaluados())))
    output$com <- renderText(formato(nrow(com())))
    output$zl <- renderText(formato(nrow(zl())))
    output$coincidencias <- renderText(
      formato(data.table::uniqueN(intersect(com()$cluster_id, zl()$cluster_id)))
    )
    output$esperados <- renderText({
      dt <- pronostico_dia()
      if (!nrow(dt)) return("No disponible")
      formato(round(dt$predicho[[1]]))
    })
  })
}
