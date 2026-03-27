#' Create a new RDesk application
#'
#' @description
#' Scaffolds a professional RDesk application with a modern dashboard layout.
#' The app includes a sidebar for filters, KPI cards, and an asynchronous
#' ggplot2 charting engine fueled by mtcars (default).
#'
#' @param name App name. Must be a valid directory name.
#' @param path Directory to create the app in. Default is current directory.
#' @param theme One of "light", "dark", "system". Default "system".
#' @param open Logical. If TRUE and in RStudio, opens the new project in a new session.
#' @param data_source Internal use. Defaults to "builtin".
#' @param viz_type Internal use. Defaults to "mixed".
#' @param use_async Internal use. Defaults to TRUE.
#'
#' @return Path to the created app directory, invisibly.
#' @examples
#' if (interactive()) {
#'   # Create the Professional Hero Dashboard in a temporary directory
#'   rdesk_create_app("MyDashboard", path = tempdir())
#' }
#' 
#' # The following demonstrates just the return value without opening a window
#' # (Fast and safe - no \dontrun needed for this specific logical check)
#' path <- file.path(tempdir(), "TestLogic")
#' if (!dir.exists(path)) {
#'   # This is just a placeholder example of how to call the function safely
#'   message("Scaffold path will be: ", path)
#' }
#' @export
rdesk_create_app <- function(name,
                              path        = tempdir(),
                              data_source = NULL,
                              viz_type    = NULL,
                              use_async   = NULL,
                              theme       = "light",
                              open        = TRUE) {

  # Validate name
  if (missing(name) || !nzchar(trimws(name))) {
    stop("[RDesk] App name is required. Example: rdesk_create_app('MyApp')")
  }
  
  name <- trimws(name)
  if (!grepl("^[A-Za-z][A-Za-z0-9._-]*$", name)) {
    stop("[RDesk] App name must start with a letter and contain only ",
         "letters, numbers, dots, hyphens, or underscores.")
  }

  # Simply default to the Hero (Advanced Dashboard) automatically
  if (is.null(data_source)) data_source <- "builtin"
  if (is.null(viz_type))    viz_type    <- "mixed"
  if (is.null(use_async))   use_async   <- TRUE
  if (is.null(theme))       theme       <- "system"

  # Ensure length 1 for all parameters
  data_source <- as.character(data_source)[1]
  viz_type    <- as.character(viz_type)[1]
  use_async   <- isTRUE(use_async[1])
  theme       <- as.character(theme)[1]

  # Create app directory
  app_dir <- normalizePath(file.path(path, name), mustWork = FALSE)
  if (dir.exists(app_dir)) {
    stop("[RDesk] Directory already exists: ", app_dir,
         "\nChoose a different name or delete the existing directory.")
  }

  message("\n[RDesk] Generating ", name, "...")

  # Generate from template
  rdesk_scaffold_files(
    app_dir     = app_dir,
    name        = name,
    data_source = data_source,
    viz_type    = viz_type,
    use_async   = isTRUE(use_async),
    theme       = theme
  )

  # Success message
  rdesk_scaffold_success_msg(name, app_dir, data_source, viz_type, use_async)

  # Open in RStudio if available
  if (open && requireNamespace("rstudioapi", quietly = TRUE)) {
    if (rstudioapi::isAvailable()) {
      rstudioapi::openProject(app_dir, newSession = TRUE)
    }
  }

  invisible(app_dir)
}


#' Internal success message
#' @keywords internal
rdesk_scaffold_success_msg <- function(name, app_dir, data_source, viz_type, use_async) {
  message("\n[RDesk] Successfully created: ", app_dir, "\n")
  message("[RDesk] Your Professional Dashboard includes:")
  message("  - Mixed visualization (Charts + Tables)")
  message("  - Built-in KPI cards system")
  message("  - Sidebar filtering engine")
  message("  - Background processing (Async Workers)")
  message("\n[RDesk] Run it now:")
  message(sprintf("  setwd(%s)\n", shQuote(normalizePath(app_dir, winslash = "\\"))))
  message("  source(\"app.R\")\n\n")
  message("[RDesk] Build your executable when ready:")
  message(sprintf("  RDesk::build_app(app_dir = %s, app_name = %s)\n\n",
              shQuote(normalizePath(app_dir, winslash = "\\")), shQuote(name)))
}


#' @keywords internal
rdesk_scaffold_files <- function(app_dir, name, data_source,
                                  viz_type, use_async, theme) {
  # Directory structure
  dirs <- c(app_dir,
            file.path(app_dir, "R"),
            file.path(app_dir, "www"),
            file.path(app_dir, "www", "css"),
            file.path(app_dir, "www", "js"),
            file.path(app_dir, "data"))
  lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE)

  # Template variables available to all templates
  vars <- list(
    APP_NAME    = name,
    APP_TITLE   = gsub("[._-]", " ", name),
    DATA_SOURCE = data_source,
    VIZ_TYPE    = viz_type,
    USE_ASYNC   = use_async,
    THEME       = theme,
    RDESK_VER   = as.character(utils::packageVersion("RDesk")),
    DATE        = format(Sys.Date(), "%Y-%m-%d")
  )

  # Write each file from its template
  rdesk_write_template("app.R",           file.path(app_dir, "app.R"),           vars)
  rdesk_write_template("DESCRIPTION",     file.path(app_dir, "DESCRIPTION"),     vars)
  
  # Server variant based on async
  rdesk_write_template("R/server.R",      file.path(app_dir, "R", "server.R"),   vars,
                        variant = if (use_async) "async" else "sync")
                        
  rdesk_write_template("R/data.R",        file.path(app_dir, "R", "data.R"),     vars,
                        variant = data_source)
  rdesk_write_template("R/plots.R",       file.path(app_dir, "R", "plots.R"),    vars,
                        variant = viz_type)
  rdesk_write_template("www/index.html",  file.path(app_dir, "www", "index.html"), vars,
                        variant = viz_type)
  rdesk_write_template("www/css/style.css", file.path(app_dir, "www", "css", "style.css"), vars,
                        variant = theme)
  rdesk_write_template("www/js/app.js",   file.path(app_dir, "www", "js", "app.js"), vars,
                        variant = viz_type)
  rdesk_write_template("data/README.md",  file.path(app_dir, "data", "README.md"), vars)

  # Copy rdesk.js from package
  rdesk_js_src <- system.file("www", "rdesk.js", package = "RDesk")
  if (!nzchar(rdesk_js_src)) {
    # Fallback for dev mode
    rdesk_js_src <- file.path(find.package("RDesk"), "inst", "www", "rdesk.js")
  }
  
  if (!nzchar(rdesk_js_src) || !file.exists(rdesk_js_src)) {
    warning("[RDesk] Could not find rdesk.js - copy it manually from inst/www/rdesk.js")
  } else {
    file.copy(rdesk_js_src, file.path(app_dir, "www", "js", "rdesk.js"))
  }

  message("[RDesk]   Created ", length(dirs), " directories and 8 files")
  invisible(app_dir)
}


#' @keywords internal
rdesk_write_template <- function(template_name, dest_path, vars, variant = NULL) {
  # Look for variant-specific template first, fall back to base template
  template_dir <- system.file("templates/app_skeleton", package = "RDesk")
  if (!nzchar(template_dir)) {
    # Fallback for dev mode
    template_dir <- file.path(find.package("RDesk"), "inst", "templates", "app_skeleton")
  }

  candidates <- c(
    if (!is.null(variant) && nzchar(variant))
      file.path(template_dir, paste0(template_name, ".", variant)),
    file.path(template_dir, template_name)
  )

  template_path <- candidates[file.exists(candidates)][1]
  if (is.na(template_path)) {
    # One more try - default to the non-variant file if it exists
    template_path <- file.path(template_dir, template_name)
  }

  if (!file.exists(template_path)) {
    warning("[RDesk] Template not found: ", template_name, " (variant: ", variant, ") - skipping")
    return(invisible(NULL))
  }

  content <- paste(readLines(template_path, warn = FALSE), collapse = "\n")

  # Replace all {{VAR_NAME}} placeholders
  for (nm in names(vars)) {
    val     <- vars[[nm]]
    if (is.logical(val)) {
        val <- tolower(as.character(val))
    } else {
        val <- as.character(val)
    }
    # Ensure length 1 to avoid gsub warnings/errors
    if (length(val) > 1) val <- paste(val, collapse = ", ")
    
    content <- gsub(paste0("\\{\\{", nm, "\\}\\}"), val, content)
  }

  writeLines(content, dest_path)
  invisible(dest_path)
}
