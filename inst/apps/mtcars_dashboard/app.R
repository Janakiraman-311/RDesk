# inst/apps/mtcars_dashboard/app.R
# Thin entry point

resolve_app_dir <- function() {
  # source() exposes the sourced file as `ofile`; prefer it over the
  # active editor document or the outer script that launched the app.
  for (i in rev(seq_len(sys.nframe()))) {
    frame <- sys.frame(i)
    if (!exists("ofile", envir = frame, inherits = FALSE)) next

    ofile <- get("ofile", envir = frame)
    if (is.character(ofile) && length(ofile) == 1L &&
        nzchar(ofile) && file.exists(ofile)) {
      return(dirname(normalizePath(ofile, winslash = "/", mustWork = TRUE)))
    }
  }

  args <- commandArgs(trailingOnly = FALSE)

  # Check for Rscript --file=...
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/", mustWork = FALSE)
    if (nzchar(script_path) && file.exists(script_path)) {
      return(dirname(script_path))
    }
  }

  # Check for R -f ...
  f_idx <- which(args == "-f")
  if (length(f_idx) > 0 && f_idx < length(args)) {
    script_path <- normalizePath(args[f_idx + 1], winslash = "/", mustWork = FALSE)
    if (nzchar(script_path) && file.exists(script_path)) {
      return(dirname(script_path))
    }
  }

  # Fallback for bundled launchers that do not pass a script path.
  if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    return(normalizePath(getwd(), winslash = "/", mustWork = TRUE))
  }

  if (!nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    rstudio_path <- tryCatch(rstudioapi::getActiveDocumentContext()$path, error = function(e) "")
    if (is.character(rstudio_path) && length(rstudio_path) == 1L &&
        nzchar(rstudio_path) && basename(rstudio_path) == "app.R" &&
        file.exists(rstudio_path)) {
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

# Force callr backend in bundled mode to avoid nanonext/mirai daemon socket
# conflicts with the processx pipe-based launcher IPC.
if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
  options(rdesk.async_backend = "callr")
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

invisible(lapply(r_files, function(path) source(path, local = .GlobalEnv)))

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

  # Enable hot reload in development mode!
  if (is_dev && !nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    rdesk_watch(app)
  }

  if (!exists("init_handlers", mode = "function", envir = .GlobalEnv,
              inherits = FALSE)) {
    stop("[mtcars_dashboard] init_handlers() was not loaded from ", r_dir)
  }
  init_handlers(app, .env)

  app$run()

}, error = function(e) {
  if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    cat(sprintf("\n[%s] CRITICAL ERROR:\n%s\n", Sys.time(), e$message))
  }
  stop(e)
})
