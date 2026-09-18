abrir_detalle_com <- function() {
  abrir_detalle_local_app()
}

preparar_historia_com <- function() {
  serie <- arrow::open_dataset(resolver_path_serie_app()) |>
    dplyr::filter(escenario == "P3_compacto") |> dplyr::collect() |> data.table::as.data.table()
  if (!usar_s3_app()) {
    ds <- abrir_detalle_com()
    fechas <- ds |>
      dplyr::filter(modelo_id == "com_reclamo", estado_observacion == "cerrado") |>
      dplyr::distinct(dia_objetivo) |> dplyr::collect()
    dias_detalle <- as.character(fechas$dia_objetivo)
  } else {
    ds <- NULL
    dias_detalle <- listar_dias_detalle_s3_app("com_reclamo")
    if (length(dias_detalle)) {
      cierre <- max(as.Date(dias_detalle)) - dias_validacion_app()
      dias_detalle <- dias_detalle[as.Date(dias_detalle) <= cierre]
    }
  }
  # Los criterios de cupos requieren pronostico agregado disponible.
  dias <- sort(intersect(dias_detalle, as.character(serie$dia_objetivo)))
  list(
    ds = ds,
    serie = serie,
    dias = dias,
    cargar_dia = function(fecha) {
      cargar_detalle_dia_app(fecha, "com_reclamo", ds_local = ds)
    }
  )
}

crear_grilla_com <- function(centroides, metros) {
  pts <- sf::st_as_sf(as.data.frame(centroides), coords = c("lng", "lat"), crs = 4326) |>
    sf::st_transform(32721)
  grid <- sf::st_make_grid(pts, cellsize = metros, square = FALSE)
  hits <- sf::st_intersects(pts, grid)
  ids <- vapply(hits, function(x) if (length(x)) x[1] else NA_integer_, integer(1))
  stopifnot(!anyNA(ids))
  list(mapa = sf::st_sf(hex_id = seq_along(grid), geometry = grid) |> sf::st_transform(4326),
       asignacion = data.table::data.table(cluster_id = centroides$cluster_id, hex_id = ids))
}

distribucion_com <- function(grilla, dia, seleccionados) {
  dt <- merge(dia, grilla$asignacion, by = "cluster_id", all.x = TRUE)
  stopifnot(!anyNA(dt$hex_id))
  dt[, seleccionado := cluster_id %in% seleccionados$cluster_id]
  conteos <- dt[, .(seleccionados = sum(seleccionado),
                    observados = sum(tuvo_reclamo_observado == 1L)), by = hex_id]
  conteos[, pct_sel := if (sum(seleccionados) > 0) 100 * seleccionados / sum(seleccionados) else NA_real_]
  conteos[, pct_obs := if (sum(observados) > 0) 100 * observados / sum(observados) else NA_real_]
  merge(grilla$mapa, as.data.frame(conteos), by = "hex_id")
}

dia_com_ui <- function(id, historia) {
  ns <- NS(id)
  layout_sidebar(
    sidebar = sidebar(width = 265,
      selectInput(ns("dia"), "D\u00eda cerrado", choices = setNames(historia$dias,
        format(as.Date(historia$dias), "%d/%m/%Y")), selected = tail(historia$dias, 1)),
      seleccion_ui(ns("seleccion"), "com"),
      selectInput(ns("tamano"), "Ancho del hex\u00e1gono", c("500 m" = 500, "1 km" = 1000, "2 km" = 2000), selected = 1000),
      p("Cada mapa distribuye su propio total (100 %). Se compara la concentraci\u00f3n territorial, no el acierto punto a punto.")),
    div(class = "day-com-page",
      textOutput(ns("resumen")),
      layout_columns(col_widths = c(6, 6),
        card(card_header("Distribuci\u00f3n de seleccionados"),
          checkboxInput(ns("puntos_seleccionados"), "Mostrar puntos seleccionados", FALSE),
          leafletOutput(ns("seleccionados"), height = "64vh")),
        card(card_header("Distribuci\u00f3n de observados"),
          checkboxInput(ns("puntos_observados"), "Mostrar puntos observados", FALSE),
          leafletOutput(ns("observados"), height = "64vh"))),
      card(card_header("Comparaci\u00f3n de estrategias de selecci\u00f3n"),
        p("Todos los criterios usan los par\u00e1metros de los controles COM para el d\u00eda elegido. Precisi\u00f3n: capturados / seleccionados; cobertura: capturados / observados; lift: precisi\u00f3n / prevalencia. Estas m\u00e9tricas miden coincidencia por cluster."),
        DTOutput(ns("metricas")))))
}

dia_com_server <- function(id, historia, centroides, version_cluster) {
  moduleServer(id, function(input, output, session) {
    dia <- reactive({
      req(input$dia)
      fecha <- as.Date(input$dia)
      dt <- historia$cargar_dia(fecha)
      validate(need(nrow(dt) > 0, "Sin datos para este d\u00eda."),
        need(all(dt$estado_observacion == "cerrado") && !anyNA(dt$tuvo_reclamo_observado), "El d\u00eda no est\u00e1 cerrado."),
        need(all(dt$version_cluster == version_cluster), "La versi\u00f3n territorial no coincide."),
        need(!anyDuplicated(dt$cluster_id), "Clusters duplicados."),
        need(all(dt$cluster_id %in% centroides$cluster_id), "Faltan coordenadas: no se comparar\u00e1 un universo incompleto."))
      merge(dt, centroides, by = "cluster_id", all.x = TRUE)
    })
    agregado <- reactive(historia$serie[as.character(dia_objetivo) == input$dia & nivel_territorial == "montevideo", .(predicho = clusters_estimados)])
    barrios <- reactive(historia$serie[as.character(dia_objetivo) == input$dia & nivel_territorial == "barrio", .(barrio = territorio_nombre, predicho = clusters_estimados)])
    seleccion <- seleccion_server("seleccion", "com", dia, agregado, barrios)
    metricas <- reactive({
      dt <- dia()
      positivos <- sum(dt$tuvo_reclamo_observado == 1L)
      prevalencia <- positivos / nrow(dt)
      selecciones <- seleccion$comparar()
      etiquetas <- c("Porcentaje global", "Cantidad global fija", "Umbral de score",
        "Total sugerido por el modelo", "Porcentaje dentro de cada barrio",
        "Cantidad fija por barrio", "Cupos estimados por barrio", "Repartir capacidad por barrio")
      data.table::rbindlist(lapply(seq_along(selecciones), function(i) {
        s <- selecciones[[i]]; metodo <- names(selecciones)[i]
        capturados <- sum(s$tuvo_reclamo_observado == 1L)
        precision <- if (nrow(s)) capturados / nrow(s) else NA_real_
        data.table::data.table(activa = if (metodo == seleccion$estrategia()) "Activa" else "",
          estrategia = etiquetas[i], parametro = seleccion$parametros()[[metodo]],
          seleccionados = nrow(s), seleccionados_evaluables = nrow(s),
          observados_capturados = capturados, precision = precision,
          cobertura = if (positivos > 0) capturados / positivos else NA_real_,
          lift = if (prevalencia > 0) precision / prevalencia else NA_real_)
      }))
    })
    output$metricas <- renderDT({
      datatable(metricas(), rownames = FALSE,
        colnames = c("", "Estrategia", "Par\u00e1metro", "Seleccionados",
          "Seleccionados evaluables", "Observados capturados", "Precisi\u00f3n", "Cobertura", "Lift"),
        options = list(dom = "t", ordering = TRUE, pageLength = 8, scrollX = TRUE)) |>
        formatPercentage(c("precision", "cobertura"), digits = 1) |>
        formatRound("lift", digits = 2)
    })
    grilla <- reactive({ req(input$tamano); crear_grilla_com(centroides, as.numeric(input$tamano)) })
    distribucion <- reactive(distribucion_com(grilla(), dia(), seleccion$seleccion()))
    output$resumen <- renderText({
      dt <- dia(); n <- nrow(seleccion$seleccion()); obs <- sum(dt$tuvo_reclamo_observado == 1)
      estimado <- agregado()$predicho
      estimado_txt <- if (length(estimado) && is.finite(estimado[[1]])) {
        format(round(estimado[[1]]), big.mark = ".", decimal.mark = ",")
      } else {
        "No disponible"
      }
      paste0(nrow(dt), " evaluados \u00b7 ", n, " seleccionados \u00b7 ", obs,
        " observados \u00b7 ", estimado_txt, " estimados",
        if (!n || !obs) " \u00b7 Sin distribuci\u00f3n para el total igual a cero." else "")
    })
    for (nombre in c("seleccionados", "observados")) local({
      id_mapa <- nombre
      output[[id_mapa]] <- renderLeaflet(leaflet(options = leafletOptions(preferCanvas = TRUE)) |>
        addProviderTiles(providers$CartoDB.Positron) |> setView(-56.16, -34.86, 11))
      observe({
        h <- distribucion()
        limite <- max(c(h$pct_sel, h$pct_obs, 1), na.rm = TRUE)
        pal <- colorNumeric(c("#f7fbff", "#6baed6", "#08306b"), c(0, limite), na.color = "#dddddd")
        h$valor <- if (id_mapa == "seleccionados") h$pct_sel else h$pct_obs
        h$etiqueta <- paste0("Hex\u00e1gono ", h$hex_id, " | Seleccionados: ", h$seleccionados,
          " (", ifelse(is.na(h$pct_sel), "no calculable", paste0(round(h$pct_sel, 2), "%")),
          ") | Observados: ", h$observados, " (",
          ifelse(is.na(h$pct_obs), "no calculable", paste0(round(h$pct_obs, 2), "%")), ")")
        leafletProxy(id_mapa, session = session) |> clearGroup("hexagonos") |> clearControls() |>
          addPolygons(data = h, group = "hexagonos", color = "#88939b", weight = 0.4, fillOpacity = 0.8,
            fillColor = ~pal(valor), label = ~etiqueta) |>
          addLegend(pal = pal, values = c(0, limite), title = "% del total", opacity = 0.8)
      })
      observe({
        mostrar <- isTRUE(input[[paste0("puntos_", id_mapa)]])
        puntos <- if (id_mapa == "seleccionados") seleccion$seleccion() else dia()[tuvo_reclamo_observado == 1L]
        proxy <- leafletProxy(id_mapa, session = session) |> clearGroup("puntos")
        if (mostrar && nrow(puntos)) {
          proxy |> addCircleMarkers(data = puntos, lng = ~lng, lat = ~lat,
            group = "puntos", radius = 4, weight = 1, color = "#ffffff",
            fillColor = if (id_mapa == "seleccionados") "#d14900" else "#6a1b9a",
            fillOpacity = 0.9, label = ~paste("Cluster", cluster_id))
        }
      })
    })
    # Sincronizacion bidireccional; comparar centros evita el rebote entre mapas.
    for (origen in c("seleccionados", "observados")) local({
      src <- origen; dst <- if (src == "seleccionados") "observados" else "seleccionados"
      observeEvent(input[[paste0(src, "_center")]], {
        centro <- input[[paste0(src, "_center")]]
        otro <- input[[paste0(dst, "_center")]]
        zoom <- input[[paste0(src, "_zoom")]]
        req(centro, zoom)
        if (is.null(otro) || abs(centro$lat - otro$lat) > 1e-6 || abs(centro$lng - otro$lng) > 1e-6 ||
            !identical(zoom, input[[paste0(dst, "_zoom")]])) {
          leafletProxy(dst, session = session) |> setView(centro$lng, centro$lat, zoom)
        }
      })
    })
    list(dia = dia, distribucion = distribucion)
  })
}
