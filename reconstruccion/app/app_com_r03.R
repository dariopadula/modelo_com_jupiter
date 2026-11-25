# Interfaz R03 de solo lectura; Shiny establece el directorio de la app.
root <- normalizePath("..", winslash = "/", mustWork = TRUE)
source("seleccion_com.R", local = TRUE)
source("datos_com.R", local = TRUE)
source("mod_com.R", local = TRUE)
data <- rf_read_com_product(root)
ui <- bslib::page_fluid(title = "Reconstrucción COM", theme = bslib::bs_theme(version = 5,
  primary = "#087f8c"), shiny::h2("Prioridad operativa — muestra COM"), rf_com_ui("com"))

# Conecta el modulo COM con el producto ya cargado.  Entradas: contexto del servidor
# Shiny. Salida: modulo reactivo.
server <- function(input, output, session) rf_com_server("com", data)
shiny::shinyApp(ui, server)
