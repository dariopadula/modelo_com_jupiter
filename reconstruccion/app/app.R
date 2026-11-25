# App R08 de solo lectura: fija una publicacion propia y conecta UI/server separados.
root <- normalizePath("..", winslash = "/", mustWork = TRUE)
app_env <- environment()
source(file.path(root, "R/configuracion/runtime_r07.R"), encoding = "UTF-8")
rf_init_r07()
library(shiny)
library(bslib)
library(leaflet)
library(DT)
library(plotly)
library(sf)
library(arrow)
library(data.table)

for (file in c("acceso/configuracion.R", "acceso/almacen.R", "publicacion/versiones.R",
    "acceso/lector_app.R")) {
  source(file.path(root, "R", file), local = app_env, encoding = "UTF-8")
}

for (file in c("datos_app.R", "datos_fuente.R", "datos_operacion.R", "mod_seleccion.R",
    "mod_resumen.R", "mod_mapa.R", "mod_lista.R", "mod_scores.R", "mod_evolucion.R",
    "mod_dia_com.R", "mod_dia_zl.R")) {
  source(file.path("R", file), local = app_env, encoding = "UTF-8")
}
historia_com <- preparar_historia_com()
historia_zl <- preparar_historia_zl()
serie_evolucion <- cargar_serie_evolucion()
datos_app <- cargar_datos_operacion()
predicciones <- datos_app$predicciones
pronostico_agregado <- datos_app$agregado_dia
pronostico_barrio <- datos_app$agregado_barrio
dia_operativo <- datos_app$dia_operativo
fecha_operativa_texto <- format(as.Date(dia_operativo), "%d/%m/%Y")

# Entrega una copia de los scores del dia al modulo de cada familia.
datos_modelo_dia <- function(modelo) {
  data.table::copy(predicciones[dia_objetivo == dia_operativo & modelo_id == modelo])
}
source("interfaz.R", local = app_env, encoding = "UTF-8")
ui <- crear_ui_app(
  fecha_operativa_texto = fecha_operativa_texto,
  publication_label = .rf_publication$label,
  serie_evolucion = serie_evolucion,
  historia_com = historia_com,
  historia_zl = historia_zl
)
source("servidor.R", local = app_env, encoding = "UTF-8")
shiny::shinyApp(ui, server)
