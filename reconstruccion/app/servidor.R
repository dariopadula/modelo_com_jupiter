# Conecta modulos de lectura y seleccion; no calcula features ni modelos.
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

