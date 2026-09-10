# Solo se materializa la serie agregada COM de evaluacion, nunca el detalle.
cargar_serie_evolucion <- function() {
  base <- Sys.getenv("APP_HISTORICO_PATH", "data/historico")
  path <- file.path(base, "serie_historica_com")
  if (!dir.exists(path)) return(data.table::data.table())
  dt <- arrow::open_dataset(path) |>
    dplyr::filter(nivel_territorial == "montevideo", escenario == "P3_compacto",
                  split_modelo %in% c("validacion", "test"), estado_observacion == "cerrado") |>
    dplyr::collect() |>
    data.table::as.data.table()
  dt[, dia_objetivo := as.Date(dia_objetivo)]
  if (anyDuplicated(dt$dia_objetivo)) stop("Fechas duplicadas en la serie COM")
  data.table::setorder(dt, dia_objetivo)
  dt
}

metricas_evolucion <- function(dt) {
  ok <- is.finite(dt$clusters_observados) & is.finite(dt$clusters_estimados)
  y <- dt$clusters_observados[ok]
  p <- dt$clusters_estimados[ok]
  n <- length(y)
  if (!n) return(c(correlacion = NA_real_, r2 = NA_real_, rmse = NA_real_, mae = NA_real_))
  error <- p - y
  sst <- sum((y - mean(y))^2)
  c(correlacion = if (n > 1L && sd(y) > 0 && sd(p) > 0) cor(y, p) else NA_real_,
    r2 = if (n > 1L && sst > 0) 1 - sum(error^2) / sst else NA_real_,
    rmse = sqrt(mean(error^2)), mae = mean(abs(error)))
}

filtrar_lunes_evolucion <- function(dt) {
  dt[format(dia_objetivo, "%u") == "1"]
}

evolucion_ui <- function(id, serie) {
  ns <- NS(id)
  fechas <- if (nrow(serie)) range(serie$dia_objetivo) else rep(Sys.Date(), 2)
  div(class = "evolution-page",
    div(class = "evolution-toolbar",
      dateRangeInput(ns("periodo"), "Per\u00edodo a evaluar", start = fechas[1],
        end = fechas[2], min = fechas[1], max = fechas[2], language = "es",
        format = "dd/mm/yyyy", separator = "a"),
      actionButton(ns("restablecer"), "Toda la evaluaci\u00f3n"),
      span("Montevideo \u00b7 COM \u00b7 Validaci\u00f3n y test. Entrenamiento excluido.")
    ),
    card(card_header("Clusters con reclamo: estimados y observados"),
         p(class = "evolution-chart-note", "Los puntos sobre las l\u00edneas identifican los lunes."),
         plotlyOutput(ns("serie"), height = "360px")),
    card(card_header("Desempe\u00f1o del modelo"),
         uiOutput(ns("comparacion")),
         tags$details(tags$summary("C\u00f3mo interpretar las m\u00e9tricas"),
           p("Correlaci\u00f3n: acompa\u00f1amiento de las variaciones observadas, entre -1 y 1."),
           p("R\u00b2 predictivo = 1 - suma de errores cuadrados / suma de desviaciones observadas al cuadrado. Usa la media del per\u00edodo de cada columna: 1 es perfecto, 0 equivale a esa media y puede ser negativo. No es correlaci\u00f3n al cuadrado."),
           p("RMSE y MAE se expresan en clusters; menor es mejor. RMSE penaliza m\u00e1s los errores grandes. Se usan solamente pares estimado/observado finitos.")))
  )
}

evolucion_server <- function(id, serie) {
  moduleServer(id, function(input, output, session) {
    observeEvent(input$restablecer, {
      req(nrow(serie))
      updateDateRangeInput(session, "periodo", start = min(serie$dia_objetivo), end = max(serie$dia_objetivo))
    })
    periodo <- reactive({
      validate(need(nrow(serie) > 0, "No hay serie de evaluaci\u00f3n disponible. Revise APP_HISTORICO_PATH."))
      req(length(input$periodo) == 2L, !anyNA(input$periodo))
      validate(need(input$periodo[1] <= input$periodo[2], "El inicio debe ser anterior al final."))
      serie[dia_objetivo >= as.Date(input$periodo[1]) & dia_objetivo <= as.Date(input$periodo[2])]
    })
    output$serie <- renderPlotly({
      dt <- periodo()
      validate(need(nrow(dt) > 0, "No hay datos de validaci\u00f3n o test en este per\u00edodo."))
      lunes <- filtrar_lunes_evolucion(dt)
      plot_ly(dt, x = ~dia_objetivo) |>
        add_trace(y = ~clusters_observados, name = "Observados", type = "scatter", mode = "lines",
          line = list(color = "#344054", width = 2)) |>
        add_trace(y = ~clusters_estimados, name = "Estimados", type = "scatter", mode = "lines",
          line = list(color = "#087f8c", width = 2, dash = "dot")) |>
        add_trace(data = lunes, x = ~dia_objetivo, y = ~clusters_observados,
          type = "scatter", mode = "markers", name = "Lunes observados",
          marker = list(size = 8, color = "#344054", line = list(color = "#ffffff", width = 1)),
          showlegend = FALSE, hoverinfo = "skip", inherit = FALSE) |>
        add_trace(data = lunes, x = ~dia_objetivo, y = ~clusters_estimados,
          type = "scatter", mode = "markers", name = "Lunes estimados",
          marker = list(size = 8, color = "#087f8c", line = list(color = "#ffffff", width = 1)),
          showlegend = FALSE, hoverinfo = "skip", inherit = FALSE) |>
        layout(hovermode = "x unified", xaxis = list(title = "", tickformat = "%d/%m/%Y"),
          yaxis = list(title = "Clusters con reclamo", rangemode = "tozero"),
          legend = list(orientation = "h", x = 0, y = 1.12),
          margin = list(l = 65, r = 20, b = 45, t = 35))
    })
    output$comparacion <- renderUI({
      dt <- periodo()
      describir <- function(x) {
        ok <- is.finite(x$clusters_observados) & is.finite(x$clusters_estimados)
        x <- x[ok]
        if (!nrow(x)) return("0 d\u00edas evaluados")
        paste0(format(min(x$dia_objetivo), "%d/%m/%Y"), " a ",
          format(max(x$dia_objetivo), "%d/%m/%Y"), " \u00b7 ", nrow(x), " d\u00edas evaluados")
      }
      fmt <- function(x) if (is.finite(x)) formatC(x, digits = 3, format = "f", decimal.mark = ",") else "No calculable"
      actual <- metricas_evolucion(dt)
      total <- metricas_evolucion(serie)
      etiquetas <- c("Correlaci\u00f3n", "R\u00b2 predictivo", "RMSE (clusters)", "MAE (clusters)")
      div(class = "table-responsive", tags$table(class = "table table-striped evolution-metrics",
        tags$thead(tags$tr(tags$th("M\u00e9trica"),
          tags$th("Per\u00edodo seleccionado", tags$small(describir(dt))),
          tags$th("Validaci\u00f3n + test", tags$small(describir(serie))))),
        tags$tbody(lapply(seq_along(etiquetas), function(i)
          tags$tr(tags$th(etiquetas[i], scope = "row"), tags$td(fmt(actual[i])), tags$td(fmt(total[i])))))))
    })
    list(periodo = periodo)
  })
}
