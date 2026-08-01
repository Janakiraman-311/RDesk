# RDesk Data Intelligence Studio
# Demonstrates: async, progress, native menus, file dialogs,
# per-user storage, recent files, toast notifications, charts, tables

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

library(RDesk)
options(rdesk.async_backend = "callr") # Force callr backend for robust, firewall-immune process pipe IPC

lapply(
  list.files(file.path(app_dir, "R"),
             pattern = "\\.R$", full.names = TRUE),
  source
)

app <- App$new(
  title           = "Data Intelligence Studio",
  width           = 1280L,
  height          = 820L,
  www             = file.path(app_dir, "www")
)

if (!rdesk_is_bundle()) rdesk_watch(app)

init_handlers(app)
app$run()
