meses_existentes <- function(path) {
  if (!dir.exists(path)) return(integer())
  
  dirs <- list.dirs(path, recursive = TRUE, full.names = FALSE)
  
  meses <- as.integer(sub(".*anio_mes=", "", dirs[grepl("anio_mes=", dirs)]))
  
  as.integer(meses)
}
