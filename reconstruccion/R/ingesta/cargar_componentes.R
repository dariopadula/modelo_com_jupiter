# Carga solo los componentes propios de procesamiento COM.  Entradas: raiz nueva y
# entorno destino. Salida: funciones disponibles en ese entorno.
rf_load_com_components <- function(root, envir = parent.frame()) {
  files <- c("ingesta/preparar_datos_com.R", "ingesta/definir_intervalos_actividad_contenedor.R",
    "ingesta/preparar_datos_levante.R", "referencias/vecinos_cercanos.R", "referencias/asignar_puntos_a_clusters_referencia.R",
    "referencias/asignar_posiciones_levante_a_clusters.R", "referencias/asignar_com_a_contenedores_activos.R",
    "features/construir_base_cluster_dia.R", "features/construir_features_historicas_cluster_dia.R",
    "ingesta/procesar_datos_com.R")
  for (file in files) {
    source(file.path(root, "R", file), local = envir)
  }
  invisible(files)
}
