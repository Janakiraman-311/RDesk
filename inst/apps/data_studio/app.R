# RDesk Data Intelligence Studio
# Demonstrates: async, progress, native menus, file dialogs,
# per-user storage, recent files, toast notifications, charts, tables

resolve_app_dir <- function() {
  # Bundled stubs provide the authoritative app root.
  bundle_root <- Sys.getenv("R_BUNDLE_ROOT")
  if (nzchar(bundle_root)) {
    bundled_app <- file.path(bundle_root, "app")
    if (file.exists(file.path(bundled_app, "app.R"))) {
      return(normalizePath(bundled_app, winslash = "/", mustWork = TRUE))
    }
  }

  # source() exposes the sourced file as `ofile`; prefer it over the
  # active editor document, which may be a different script.
  for (i in rev(seq_len(sys.nframe()))) {
    frame <- sys.frame(i)
    if (!exists("ofile", envir = frame, inherits = FALSE)) next

    ofile <- get("ofile", envir = frame)
    if (is.character(ofile) && length(ofile) == 1L &&
        nzchar(ofile) && file.exists(ofile)) {
      return(dirname(normalizePath(ofile, winslash = "/", mustWork = TRUE)))
    }
  }

  # Support Rscript/R -f launches outside the working directory.
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

  # Fallback for bundled launchers that do not pass a script path.
  if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    return(normalizePath(getwd(), winslash = "/", mustWork = TRUE))
  }

  # Use the editor context only when it actually refers to this app.
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
pkg_root <- dirname(dirname(dirname(app_dir)))
is_dev   <- file.exists(file.path(pkg_root, "DESCRIPTION")) &&
            file.exists(file.path(pkg_root, "R", "App.R"))

if (!nzchar(Sys.getenv("R_BUNDLE_APP")) && is_dev) {
  message("[RDesk] Dev mode detected. Loading local source from: ", pkg_root)
  devtools::load_all(pkg_root, quiet = TRUE)
} else {
  suppressPackageStartupMessages(library(RDesk))
}

options(rdesk.async_backend = "callr") # Force callr backend for robust, firewall-immune process pipe IPC

r_files <- sort(list.files(file.path(app_dir, "R"),
                           pattern = "\\.R$", full.names = TRUE))
if (length(r_files) == 0L) {
  stop("[Data Studio] No R source files found in: ", file.path(app_dir, "R"))
}
invisible(lapply(r_files, function(path) source(path, local = .GlobalEnv)))

if (!exists("init_handlers", mode = "function", envir = .GlobalEnv,
            inherits = FALSE)) {
  stop("[Data Studio] init_handlers() was not loaded from: ",
       file.path(app_dir, "R"))
}

app <- App$new(
  title           = "Data Intelligence Studio",
  width           = 1280L,
  height          = 820L,
  www             = file.path(app_dir, "www")
)

if (!rdesk_is_bundle()) rdesk_watch(app)

init_handlers(app)
app$run()
