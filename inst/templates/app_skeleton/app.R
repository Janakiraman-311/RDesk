# {{APP_NAME}} - built with RDesk {{RDESK_VER}}
# Generated: {{DATE}}

resolve_app_dir <- function() {
  # Bundled stubs provide the authoritative app root.
  bundle_root <- Sys.getenv("R_BUNDLE_ROOT")
  if (nzchar(bundle_root)) {
    bundled_app <- file.path(bundle_root, "app")
    if (file.exists(file.path(bundled_app, "app.R"))) {
      return(normalizePath(bundled_app, winslash = "/", mustWork = TRUE))
    }
  }

  # Prefer the actual app.R path when this file is sourced by another script.
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
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0L) {
    script_path <- normalizePath(sub("^--file=", "", file_arg[1]),
                                 winslash = "/", mustWork = FALSE)
    if (file.exists(script_path)) return(dirname(script_path))
  }

  f_idx <- which(args == "-f")
  if (length(f_idx) > 0L && f_idx[1] < length(args)) {
    script_path <- normalizePath(args[f_idx[1] + 1L],
                                 winslash = "/", mustWork = FALSE)
    if (file.exists(script_path)) return(dirname(script_path))
  }

  if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    return(normalizePath(getwd(), winslash = "/", mustWork = TRUE))
  }

  rstudio_path <- tryCatch(
    rstudioapi::getActiveDocumentContext()$path,
    error = function(e) ""
  )
  if (is.character(rstudio_path) && length(rstudio_path) == 1L &&
      nzchar(rstudio_path) && basename(rstudio_path) == "app.R" &&
      file.exists(rstudio_path)) {
    return(dirname(normalizePath(rstudio_path, winslash = "/", mustWork = TRUE)))
  }

  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

app_dir <- resolve_app_dir()

# Load RDesk - dev mode or installed
find_dev_root <- function(d) {
  cur <- d
  for (i in 1:5) {
    cur <- dirname(cur)
    if (file.exists(file.path(cur, "DESCRIPTION")) &&
        file.exists(file.path(cur, "R", "App.R"))) {
      return(cur)
    }
  }
  NULL
}

dev_root <- if (!nzchar(Sys.getenv("R_BUNDLE_APP"))) find_dev_root(app_dir) else NULL
if (!is.null(dev_root)) {
  devtools::load_all(dev_root, quiet = TRUE)
} else {
  suppressPackageStartupMessages(library(RDesk))
}

suppressPackageStartupMessages(library(ggplot2))

# Source all R/ modules
r_dir <- file.path(app_dir, "R")
if (!dir.exists(r_dir)) {
  stop("[RDesk scaffold] R/ directory not found at: ", r_dir)
}
r_files <- sort(list.files(r_dir, pattern = "\\.R$", full.names = TRUE))
if (length(r_files) == 0L) {
  stop("[RDesk scaffold] No R source files found in: ", r_dir)
}
invisible(lapply(r_files, function(path) source(path, local = .GlobalEnv)))

if (!exists("init_handlers", mode = "function", envir = .GlobalEnv,
            inherits = FALSE)) {
  stop("[RDesk scaffold] init_handlers() was not loaded from: ", r_dir)
}

# Launch
app <- App$new(
  title  = "{{APP_TITLE}}",
  width  = 1100L,
  height = 740L,
  www    = file.path(app_dir, "www")
)

init_handlers(app)
app$run()
