# port <- as.integer(Sys.getenv("APP_PORT", unset = "3839"))
# host <- Sys.getenv("APP_HOST", unset = "127.0.0.1")

port <- as.integer(
  Sys.getenv(
    "CDSW_APP_PORT",
    unset = Sys.getenv("APP_PORT", unset = "3839")
  )
)

host <- "127.0.0.1"

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
app_dir <- if (length(file_arg) > 0L) {
  normalizePath(dirname(sub("^--file=", "", file_arg[[1]])), winslash = "/", mustWork = TRUE)
} else {
  normalizePath(".", winslash = "/", mustWork = TRUE)
}

shiny::runApp(appDir = app_dir, host = host, port = port, launch.browser = FALSE)
