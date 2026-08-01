# {{APP_NAME}} - built with RDesk {{RDESK_VER}}
# Generated: {{DATE}}

resolve_app_dir <- function() {
  # 1. Check if executing via source()
  for (i in rev(seq_len(sys.nframe()))) {
    frame <- sys.frame(i)
    if (exists("ofile", envir = frame, inherits = FALSE)) {
      ofile <- get("ofile", envir = frame)
      if (is.character(ofile) && nzchar(ofile) && file.exists(ofile)) {
        return(dirname(normalizePath(ofile, winslash = "/", mustWork = TRUE)))
      }
    }
  }

  # 2. Check command line arguments (e.g. Rscript --file=... or R -f ...)
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/", mustWork = FALSE)
    if (nzchar(script_path) && file.exists(script_path)) {
      return(dirname(script_path))
    }
  }

  f_idx <- which(args == "-f")
  if (length(f_idx) > 0 && f_idx < length(args)) {
    script_path <- normalizePath(args[f_idx + 1], winslash = "/", mustWork = FALSE)
    if (nzchar(script_path) && file.exists(script_path)) {
      return(dirname(script_path))
    }
  }

  # 3. Check for active document context (Positron/RStudio tab)
  if (!nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    rstudio_path <- tryCatch(rstudioapi::getActiveDocumentContext()$path, error = function(e) "")
    if (nzchar(rstudio_path) && file.exists(rstudio_path)) {
      base_name <- basename(rstudio_path)
      if (base_name %in% c("app.R", "server.R") || grepl("/apps/", rstudio_path, fixed = TRUE)) {
        return(dirname(normalizePath(rstudio_path, winslash = "/", mustWork = TRUE)))
      }
    }
  }

  # 4. Fallback to current working directory
  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

app_dir <- resolve_app_dir()

# Load RDesk - dev mode or installed
pkg_root <- dirname(dirname(dirname(app_dir)))
is_dev   <- file.exists(file.path(pkg_root, "DESCRIPTION")) &&
            file.exists(file.path(pkg_root, "R", "App.R"))

if (!nzchar(Sys.getenv("R_BUNDLE_APP")) && is_dev) {
  devtools::load_all(pkg_root, quiet = TRUE)
} else {
  library(RDesk)
}

# Source all R/ modules
lapply(
  list.files(file.path(app_dir, "R"), pattern = "\\.R$", full.names = TRUE),
  source
)

# Launch
app <- App$new(
  title  = "{{APP_TITLE}}",
  width  = 1100L,
  height = 740L,
  www    = file.path(app_dir, "www")
)

init_handlers(app)
app$run()
