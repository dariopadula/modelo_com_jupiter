# Prepara bibliotecas explicitas y UTF-8 antes de leer factores de modelos R07.
rf_init_r07 <- function() {
  version <- paste0(R.version$major, ".", sub("\\..*$", "", R.version$minor))
  library <- Sys.getenv("RF_R_LIBRARY", unset = "")
  if (!nzchar(library) && nzchar(Sys.getenv("USERPROFILE"))) {
    library <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "R", "win-library", version)
  }
  if (dir.exists(library)) {
    .libPaths(c(library, .libPaths()))
  }
  if (identical(Sys.info()[["sysname"]], "Windows")) {
    locale <- Sys.setlocale("LC_CTYPE", ".UTF-8")
    if (!nzchar(locale)) {
      stop("No se pudo habilitar UTF-8 para leer los factores del bundle A0")
    }
  }
  invisible(NULL)
}
