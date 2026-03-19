# inst/apps/mtcars_dashboard/app.R
# Thin entry point

resolve_app_dir <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/", mustWork = FALSE)
    if (nzchar(script_path) && file.exists(script_path)) {
      return(dirname(script_path))
    }
  }

  if (!nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    rstudio_path <- tryCatch(rstudioapi::getActiveDocumentContext()$path, error = function(e) "")
    if (nzchar(rstudio_path) && file.exists(rstudio_path)) {
      return(dirname(normalizePath(rstudio_path, winslash = "/", mustWork = TRUE)))
    }
  }

  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

app_dir <- resolve_app_dir()

# Development Guard: If we are inside the RDesk source tree, use load_all()
# instead of library(RDesk) to ensure our latest changes are active.
pkg_root <- dirname(dirname(dirname(app_dir)))
is_dev <- file.exists(file.path(pkg_root, "DESCRIPTION")) &&
  file.exists(file.path(pkg_root, "R", "App.R"))

if (!nzchar(Sys.getenv("R_BUNDLE_APP")) && is_dev) {
  message("[RDesk] Dev mode detected. Loading local source from: ", pkg_root)
  devtools::load_all(pkg_root)
} else {
  suppressPackageStartupMessages(library(RDesk))
}

suppressPackageStartupMessages(library(ggplot2))
suppressPackageStartupMessages(library(dplyr))

# Source all modular logic from R/
r_dir <- file.path(app_dir, "R")
if (!dir.exists(r_dir)) {
  stop("[mtcars_dashboard] R/ directory not found at: ", r_dir)
}

r_files <- sort(list.files(r_dir, pattern = "\\.R$", full.names = TRUE))
if (length(r_files) == 0) {
  stop("[mtcars_dashboard] No R source files found in: ", r_dir)
}

invisible(lapply(r_files, source))

# Handle startup logging for bundled apps
if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
  app_name <- Sys.getenv("R_APP_NAME", "CarsAnalyser")
  log_dir <- RDesk:::rdesk_log_dir(app_name)
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)

  log_file <- file.path(log_dir, "rdesk_startup.log")
  sink_conn <- file(log_file, open = "wt")
  sink(sink_conn, type = "message")

  cat(sprintf("[%s] RDesk startup initiated (Modular)\n", Sys.time()))
}

cleanup_bundle_logging <- function() {
  if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    if (sink.number(type = "message") > 0) sink(type = "message")
    if (exists("sink_conn", inherits = FALSE) && isOpen(sink_conn)) close(sink_conn)
  }
}
on.exit(cleanup_bundle_logging(), add = TRUE)

tryCatch({
  .env <- new.env(parent = .GlobalEnv)
  .env$app_dir <- app_dir
  if (!exists("init_data", mode = "function")) {
    stop("[mtcars_dashboard] init_data() was not loaded from ", r_dir)
  }
  init_data(.env)

  app <- App$new(
    title = "Motor Trend Cars Analyser - RDesk",
    width = 1100,
    height = 740,
    www = file.path(app_dir, "www")
  )

  if (exists("init_handlers")) {
    init_handlers(app, .env)
  }

  app$run()

}, error = function(e) {
  if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    cat(sprintf("\n[%s] CRITICAL ERROR:\n%s\n", Sys.time(), e$message))
  }
  stop(e)
})
