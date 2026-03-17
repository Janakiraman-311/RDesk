# inst/apps/mtcars_dashboard/app.R
# Thin entry point

library(RDesk)
library(ggplot2)
library(dplyr)

# Standardize path: use the app directory
app_dir <- if (nzchar(Sys.getenv("R_BUNDLE_APP"))) getwd() else dirname(rstudioapi::getActiveDocumentContext()$path)
# Fallback for some dev environments
if (!dir.exists(file.path(app_dir, "www"))) app_dir <- getwd()

# Source all modular logic from R/
r_dir <- file.path(app_dir, "R")
if (dir.exists(r_dir)) {
  lapply(list.files(r_dir, pattern = "\\.R$", full.names = TRUE), source)
}

# Handle startup logging for bundled apps
if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
  app_name <- Sys.getenv("R_APP_NAME", "CarsAnalyser")
  log_dir <- file.path(Sys.getenv("LOCALAPPDATA"), "RDesk", app_name)
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
  
  log_file <- file.path(log_dir, "rdesk_startup.log")
  sink_conn <- file(log_file, open = "wt")
  sink(sink_conn, type = "message")
  sink(sink_conn, type = "output")
  
  cat(sprintf("[%s] RDesk startup initiated (Modular)\n", Sys.time()))
}

tryCatch({
  # Initialize global environment for this app instance
  .env <- new.env(parent = .GlobalEnv)
  init_data(.env)
  
  app <- App$new(
    title  = "Motor Trend Cars Analyser — RDesk",
    width  = 1100,
    height = 740,
    www    = file.path(app_dir, "www")
  )

  # Initialize handlers from R/server.R
  if (exists("init_handlers")) {
    init_handlers(app, .env)
  }

  app$run()

}, error = function(e) {
  if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    cat(sprintf("\n[%s] CRITICAL ERROR:\n%s\n", Sys.time(), e$message))
    sink(); sink()
  }
  stop(e)
})
