# Construye la UI con los productos y textos resueltos por app.R.
crear_ui_app <- function(fecha_operativa_texto, publication_label, serie_evolucion,
    historia_com, historia_zl) {
  fecha_operativa_texto <- force(fecha_operativa_texto)
  publication_label <- force(publication_label)
  serie_evolucion <- force(serie_evolucion)
  historia_com <- force(historia_com)
  historia_zl <- force(historia_zl)

  tema <- bslib::bs_theme(
    version = 5,
    bg = "#f4f6f8",
    fg = "#17212b",
    primary = "#087f8c",
    secondary = "#64717d",
    border_radius = "6px"
  )

  bslib::page_navbar(
    title = "Prioridad operativa",
    theme = tema,
    fillable = TRUE,
    footer = tags$div(class = "text-muted px-3 py-2", publication_label),
    header = tags$head(
      tags$link(rel = "stylesheet", type = "text/css", href = "app.css")
    ),
    bslib::nav_panel(
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
            strong(fecha_operativa_texto),
            span(textOutput("actualizacion", inline = TRUE))
          )
        ),
        resumen_operativo_ui("resumen"),
        div(
          class = "operation-tabs",
          bslib::navset_card_tab(
            id = "vista_operativa",
            bslib::nav_panel(
              "Mapa",
              bslib::layout_sidebar(
                class = "operation-layout",
                sidebar = bslib::sidebar(
                  width = 265,
                  open = "desktop",
                  seleccion_ui("seleccion_com", "com"),
                  seleccion_ui("seleccion_zl", "zl")
                ),
                mapa_operativo_ui("mapa")
              )
            ),
            bslib::nav_panel("Scores y umbrales", scores_umbral_ui("scores")),
            bslib::nav_panel("Clusters seleccionados", lista_clusters_ui("lista"))
          )
        )
      )
    ),
    bslib::nav_panel(
      "Hist\u00f3rico",
      bslib::navset_card_tab(
        bslib::nav_panel(
          "Evoluci\u00f3n temporal",
          evolucion_ui("evolucion", serie_evolucion)
        ),
        bslib::nav_panel(
          "Evaluaci\u00f3n del d\u00eda COM",
          dia_com_ui("dia_com", historia_com)
        ),
        bslib::nav_panel(
          "Evaluaci\u00f3n del d\u00eda ZL",
          dia_zl_ui("dia_zl", historia_zl)
        )
      )
    )
  )
}
