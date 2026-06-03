# RDesk Data Intelligence Studio
# Demonstrates: async, progress, native menus, file dialogs,
# per-user storage, recent files, toast notifications, charts, tables

app_dir <- tryCatch(
  if (nzchar(Sys.getenv("R_BUNDLE_APP"))) getwd()
  else dirname(rstudioapi::getActiveDocumentContext()$path),
  error = function(e) getwd()
)

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
