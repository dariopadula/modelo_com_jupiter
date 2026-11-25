seleccion_ui <- function(id, modelo = c("com", "zl")) {
  modelo <- match.arg(modelo)
  ns <- NS(id)

  opciones <- if (modelo == "com") {
    c(
      "Porcentaje global" = "porcentaje_global",
      "Cantidad global fija" = "fijo_global",
      "Umbral de score" = "umbral",
      "Total sugerido por el modelo" = "modelo_global",
      "Porcentaje dentro de cada barrio" = "porcentaje_barrio",
      "Cantidad fija por barrio" = "fijo_barrio",
      "Cupos estimados por barrio" = "modelo_barrio",
      "Repartir capacidad por barrio" = "capacidad_barrio"
    )
  } else {
    c(
      "Porcentaje global" = "porcentaje_global",
      "Cantidad global fija" = "fijo_global",
      "Umbral de score" = "umbral",
      "Porcentaje dentro de cada barrio" = "porcentaje_barrio",
      "Cantidad fija por barrio" = "fijo_barrio"
    )
  }

  tags$details(
    class = paste("selection-details", paste0("selection-", modelo)),
    tags$summary(
      span(class = "selection-title", if (modelo == "com") "COM" else "Zona Limpia"),
      span(class = "selection-summary", textOutput(ns("resumen"), inline = TRUE))
    ),
    div(
      class = "selection-controls",
      selectInput(
        ns("estrategia"),
        "Criterio de selecci\u00f3n",
        opciones,
        selected = if (modelo == "com") "modelo_global" else "porcentaje_global"
      ),
      conditionalPanel(
        sprintf("input['%s'].indexOf('porcentaje') >= 0", ns("estrategia")),
        sliderInput(ns("porcentaje"), "Porcentaje", 1, 30, 10, step = 1)
      ),
      conditionalPanel(
        sprintf(
          "input['%s'] == 'fijo_global' || input['%s'] == 'capacidad_barrio'",
          ns("estrategia"), ns("estrategia")
        ),
        numericInput(ns("cantidad"), "Cantidad total", 500, min = 0, step = 10)
      ),
      conditionalPanel(
        sprintf("input['%s'] == 'fijo_barrio'", ns("estrategia")),
        numericInput(ns("cantidad_barrio"), "Cantidad por barrio", 10, min = 0, step = 1)
      ),
      conditionalPanel(
        sprintf("input['%s'] == 'umbral'", ns("estrategia")),
        sliderInput(ns("umbral"), "Score m\u00ednimo", 0, 1, 0.5, step = 0.01)
      )
    )
  )
}

seleccion_server <- function(id,
                             modelo = c("com", "zl"),
                             datos_dia,
                             pronostico_dia,
                             pronostico_barrio_dia) {
  modelo <- match.arg(modelo)

  moduleServer(id, function(input, output, session) {
    cupos_barrio <- function(capacidad = NULL) {
      cupos <- data.table::copy(pronostico_barrio_dia()[
        , .(barrio, estimado = pmax(predicho, 0))
      ])
      if (!nrow(cupos)) return(cupos[, cupo := integer()])

      if (is.null(capacidad)) {
        cupos[, cuota := estimado]
        capacidad <- round(sum(cupos$estimado))
      } else {
        total_estimado <- sum(cupos$estimado)
        cupos[, cuota := if (total_estimado > 0) estimado / total_estimado * capacidad else 0]
      }
      cupos[, cupo := floor(cuota)]
      faltan <- as.integer(capacidad - sum(cupos$cupo))
      if (faltan > 0L) {
        indices <- order(-(cupos$cuota - cupos$cupo))[seq_len(min(faltan, nrow(cupos)))]
        cupos[indices, cupo := cupo + 1L]
      }
      cupos[, .(barrio, estimado, cupo)]
    }

    seleccionar_estrategia <- function(estrategia) {
      dt <- data.table::copy(datos_dia())
      req(nrow(dt) > 0, input$estrategia)

      if (estrategia == "porcentaje_global") {
        return(seleccionar_top_n(dt, ceiling(nrow(dt) * input$porcentaje / 100)))
      }
      if (estrategia == "fijo_global") {
        return(seleccionar_top_n(dt, input$cantidad))
      }
      if (estrategia == "umbral") {
        return(dt[pred_prob >= input$umbral])
      }
      if (estrategia == "modelo_global") {
        total <- pronostico_dia()$predicho
        if (!length(total)) return(dt[0])
        return(seleccionar_top_n(dt, total[[1]]))
      }
      if (estrategia == "porcentaje_barrio") {
        return(seleccionar_por_barrio(dt, estrategia, input$porcentaje))
      }
      if (estrategia == "fijo_barrio") {
        return(seleccionar_por_barrio(dt, estrategia, input$cantidad_barrio))
      }
      if (estrategia %in% c("modelo_barrio", "capacidad_barrio")) {
        capacidad <- if (estrategia == "capacidad_barrio") input$cantidad else NULL
        cupos <- cupos_barrio(capacidad)
        if (!nrow(cupos)) return(dt[0])
        return(seleccionar_por_barrio(dt, estrategia, cupos = cupos[, .(barrio, cupo)]))
      }
      dt[0]
    }
    seleccion <- reactive(seleccionar_estrategia(input$estrategia))

    etiquetas <- c(
      porcentaje_global = "Porcentaje global",
      fijo_global = "Cantidad fija",
      umbral = "Umbral",
      modelo_global = "Total sugerido",
      porcentaje_barrio = "Porcentaje por barrio",
      fijo_barrio = "Cantidad por barrio",
      modelo_barrio = "Cupos por barrio",
      capacidad_barrio = "Capacidad distribuida"
    )

    output$resumen <- renderText({
      req(input$estrategia)
      paste0(
        etiquetas[[input$estrategia]],
        " - ",
        format(nrow(seleccion()), big.mark = ".", decimal.mark = ",")
      )
    })

    list(
      seleccion = seleccion,
      comparar = reactive({
        metodos <- if (modelo == "com") names(etiquetas) else c(
          "porcentaje_global", "fijo_global", "umbral",
          "porcentaje_barrio", "fijo_barrio"
        )
        stats::setNames(lapply(metodos, seleccionar_estrategia), metodos)
      }),
      parametros = reactive(c(
        porcentaje_global = paste0(input$porcentaje, "%"),
        fijo_global = as.character(input$cantidad),
        umbral = as.character(input$umbral),
        modelo_global = "Segun modelo",
        porcentaje_barrio = paste0(input$porcentaje, "%"),
        fijo_barrio = paste(input$cantidad_barrio, "por barrio"),
        modelo_barrio = "Segun modelo",
        capacidad_barrio = as.character(input$cantidad)
      )),
      estrategia = reactive(input$estrategia),
      umbral = reactive(input$umbral)
    )
  })
}
