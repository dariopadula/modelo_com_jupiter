Sys.setenv(R_USER_CACHE_DIR = file.path(tempdir(), "r-user-cache"))

library(shiny)
library(bslib)
library(leaflet)
library(DT)
library(plotly)
library(sf)
library(arrow)
library(data.table)

source(file.path("R", "datos_app.R"))
source(file.path("R", "datos_operacion.R"))
source(file.path("R", "mod_seleccion.R"))
source(file.path("R", "mod_resumen.R"))
source(file.path("R", "mod_mapa.R"))
source(file.path("R", "mod_lista.R"))
source(file.path("R", "mod_scores.R"))
source(file.path("R", "mod_evolucion.R"))
source(file.path("R", "mod_dia_com.R"))
source(file.path("R", "mod_dia_zl.R"))
historia_com <- preparar_historia_com()
historia_zl <- preparar_historia_zl()
serie_evolucion <- cargar_serie_evolucion()

datos_app <- cargar_datos_operacion()
predicciones <- datos_app$predicciones
pronostico_agregado <- datos_app$agregado_dia
pronostico_barrio <- datos_app$agregado_barrio
dia_operativo <- datos_app$dia_operativo

datos_modelo_dia <- function(modelo) {
  data.table::copy(predicciones[
    dia_objetivo == dia_operativo & modelo_id == modelo
  ])
}

tema <- bs_theme(
  version = 5,
  bg = "#f4f6f8",
  fg = "#17212b",
  primary = "#087f8c",
  secondary = "#64717d",
  border_radius = "6px"
)

ui <- page_navbar(
  title = "Prioridad operativa",
  theme = tema,
  fillable = TRUE,
  header = tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "app.css")
  ),
  nav_panel(
    "Operaci\u00f3n del d\u00eda",
    div(
      class = "operation-page",
      div(
        class = "operation-header",
        div(
          h2("Operaci\u00f3n del d\u00eda"),
          span("Decisiones para el \u00faltimo d\u00eda con predicciones")
        ),
        div(
          class = "operation-date",
          strong(format(as.Date(dia_operativo), "%d/%m/%Y")),
          span(textOutput("actualizacion", inline = TRUE))
        )
      ),
      resumen_operativo_ui("resumen"),
      div(
        class = "operation-tabs",
        navset_card_tab(
          id = "vista_operativa",
          nav_panel(
            "Mapa",
            layout_sidebar(
              class = "operation-layout",
              sidebar = sidebar(
                width = 265,
                open = "desktop",
                seleccion_ui("seleccion_com", "com"),
                seleccion_ui("seleccion_zl", "zl")
              ),
              mapa_operativo_ui("mapa")
            )
          ),
          nav_panel("Scores y umbrales", scores_umbral_ui("scores")),
          nav_panel("Clusters seleccionados", lista_clusters_ui("lista"))
        )
      )
    )
  ),
  nav_panel("Hist\u00f3rico",
      navset_card_tab(
        nav_panel("Evoluci\u00f3n temporal", evolucion_ui("evolucion", serie_evolucion)),
        nav_panel("Evaluaci\u00f3n del d\u00eda COM", dia_com_ui("dia_com", historia_com)),
        nav_panel("Evaluaci\u00f3n del d\u00eda ZL", dia_zl_ui("dia_zl", historia_zl))))
)

server <- function(input, output, session) {
  dia_com_server("dia_com", historia_com, datos_app$centroides, datos_app$version_cluster)
  dia_zl_server("dia_zl", historia_zl, datos_app$centroides, datos_app$version_cluster)
  evolucion_server("evolucion", serie_evolucion)
  com_dia <- reactive(datos_modelo_dia("com_reclamo"))
  zl_dia <- reactive(datos_modelo_dia("zl_problema"))
  agregado_dia <- reactive(pronostico_agregado[dia_objetivo == dia_operativo])
  agregado_barrio_dia <- reactive(pronostico_barrio[dia_objetivo == dia_operativo])

  seleccion_com <- seleccion_server(
    "seleccion_com",
    modelo = "com",
    datos_dia = com_dia,
    pronostico_dia = agregado_dia,
    pronostico_barrio_dia = agregado_barrio_dia
  )
  seleccion_zl <- seleccion_server(
    "seleccion_zl",
    modelo = "zl",
    datos_dia = zl_dia,
    pronostico_dia = agregado_dia,
    pronostico_barrio_dia = agregado_barrio_dia
  )

  resumen_operativo_server(
    "resumen",
    evaluados = com_dia,
    com = seleccion_com$seleccion,
    zl = seleccion_zl$seleccion,
    pronostico_dia = agregado_dia
  )
  mapa_operativo_server(
    "mapa",
    com = seleccion_com$seleccion,
    zl = seleccion_zl$seleccion,
    barrios = datos_app$barrios,
    pronostico_barrio_dia = agregado_barrio_dia
  )
  lista_clusters_server(
    "lista",
    com = seleccion_com$seleccion,
    zl = seleccion_zl$seleccion
  )
  scores_umbral_server(
    "scores",
    datos_com = com_dia,
    datos_zl = zl_dia,
    umbral_com = seleccion_com$umbral,
    umbral_zl = seleccion_zl$umbral,
    estrategia_com = seleccion_com$estrategia,
    estrategia_zl = seleccion_zl$estrategia
  )

  output$actualizacion <- renderText({
    timestamp <- com_dia()$timestamp_ejecucion
    paste("Actualizado", formatear_hora(timestamp))
  })
}

shinyApp(ui, server)
