port <- as.integer(
  Sys.getenv(
    "CDSW_APP_PORT",
    unset = Sys.getenv("APP_PORT", unset = "3839")
  )
)

host <- "127.0.0.1"

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)

candidatos_app <- c(
  if (length(file_arg) > 0L) dirname(sub("^--file=", "", file_arg[[1]])),
  "app_operativa_v2",
  "."
)
candidatos_app <- unique(candidatos_app)
es_app <- vapply(
  candidatos_app,
  function(path) file.exists(file.path(path, "app.R")),
  logical(1)
)

if (!any(es_app)) {
  stop("No se encontro app_operativa_v2/app.R desde el directorio de ejecucion")
}
app_dir <- normalizePath(
  candidatos_app[which(es_app)[1]],
  winslash = "/",
  mustWork = TRUE
)

shiny::runApp(appDir = app_dir, host = host, port = port, launch.browser = FALSE)
