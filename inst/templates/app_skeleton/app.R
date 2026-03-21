# {{APP_NAME}} — built with RDesk {{RDESK_VER}}
# Generated: {{DATE}}

# Resolve app directory
app_dir <- getwd()

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
