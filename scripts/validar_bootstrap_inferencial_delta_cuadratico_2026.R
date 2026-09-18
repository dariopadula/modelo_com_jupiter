library(data.table)

path_out <- paste0(
  "outputs/reevaluacion_2026/",
  "exploracion_inferencia_curvatura_interaccion_q30_delta/",
  "bootstrap_cuadratico_completo"
)
archivos <- c(
  "bootstrap_coeficientes.csv", "bootstrap_resumen.csv", "metadata.csv",
  "bootstrap_forma_replicas.csv", "bootstrap_forma_resumen.csv"
)
faltantes <- archivos[!file.exists(file.path(path_out, archivos))]
if (length(faltantes)) stop("Faltan salidas: ", paste(faltantes, collapse = ", "))

metadata <- fread(file.path(path_out, "metadata.csv"))
stopifnot(
  metadata$modelo == "inferencial_delta_cuadratico",
  metadata$version_split == "reevaluacion_2026_v1",
  metadata$replicas_objetivo == 50L,
  metadata$replicas_disponibles == 50L,
  metadata$n_dias_train == 365L,
  metadata$usa_test == FALSE
)

resultados <- fread(file.path(path_out, "bootstrap_coeficientes.csv"))
if (uniqueN(resultados$replica) != 50L) stop("No hay 50 replicas")
estado <- resultados[, .(
  convergio = all(convergio),
  tiene_error = any(!is.na(error) & nzchar(error))
), by = replica]
if (estado[!convergio | tiene_error, .N]) stop("Hay replicas fallidas")

resumen <- fread(file.path(path_out, "bootstrap_resumen.csv"))
terminos_clave <- c(
  "z_log_densidad_pob", "z_porc_nbi_segmento", "z_media_h",
  "z_media_q_30", "z_delta_q_7_30", "z_delta_q_7_30_sq",
  "z_media_h:z_delta_q_7_30"
)
if (!all(terminos_clave %in% resumen$termino)) stop("Faltan terminos clave")
if (resumen[termino %in% terminos_clave, any(n_replicas != 50L)]) {
  stop("Los terminos clave no tienen 50 estimaciones")
}
columnas <- c(
  "estimacion_original", "error_std_bootstrap", "q025", "q975",
  "proporcion_positiva", "proporcion_negativa", "razon_error_std"
)
if (resumen[termino %in% terminos_clave,
            any(!is.finite(as.matrix(.SD))), .SDcols = columnas]) {
  stop("El resumen contiene valores no finitos")
}

forma <- fread(file.path(path_out, "bootstrap_forma_replicas.csv"))
if (nrow(forma) != 50L || uniqueN(forma$replica) != 50L) {
  stop("La forma cuadratica no tiene 50 replicas")
}
if (forma[, any(!is.finite(delta_minimo_h_medio))]) {
  stop("Hay minimos cuadraticos no finitos")
}

cat("VALIDACION_BOOTSTRAP_CUADRATICO_2026_OK\n")
