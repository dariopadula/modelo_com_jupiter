# Carga exclusivamente los componentes propios de acceso y publicacion R09.
rf_load_access <- function(root, envir = parent.frame()) {
  files <- c("acceso/configuracion.R", "acceso/almacen.R", "publicacion/versiones.R",
    "acceso/entregas.R", "acceso/impala.R", "acceso/lector_app.R")
  for (file in files) source(file.path(root, "R", file), local = envir, encoding = "UTF-8")
  invisible(files)
}
