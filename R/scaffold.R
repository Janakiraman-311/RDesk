#' Create a new RDesk application with guided setup
#'
#' @param name App name. Must be a valid directory name.
#' @param path Directory to create the app in. Default is current directory.
#' @param data_source One of "builtin", "csv", "database", "api".
#'   If NULL (default), prompts interactively.
#' @param viz_type One of "charts", "tables", "mixed".
#'   If NULL, prompts interactively.
#' @param use_async Logical. If NULL, prompts interactively.
#' @param theme One of "light", "dark", "system". Default "light".
#' @param open Logical. If TRUE and in RStudio, opens the new project. Default TRUE.
#' @return Path to the created app directory, invisibly.
#' @examples
#' \dontrun{
#' # Create an app interactively (prompts in console)
#' rdesk_create_app("MyVisualizer")
#' 
#' # Create a specific app non-interactively
#' rdesk_create_app("MyBatchApp",
#'                  data_source = "csv",
#'                  viz_type = "tables",
#'                  use_async = TRUE)
#' }
#' @export
rdesk_create_app <- function(name,
                              path        = ".",
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

  # Interactive prompts - only when running interactively and args not supplied
  is_interactive <- interactive() && is.null(data_source)

  if (is_interactive) {
    cat("\n[RDesk] Creating new app:", name, "\n\n")

    data_source <- rdesk_prompt_choice(
      question = "What data source will your app use?",
      choices  = c(
        "builtin"  = "Built-in R datasets (good for learning RDesk)",
        "csv"      = "CSV / Excel files (local file loading)",
        "database" = "Database via DBI (SQL databases)",
        "api"      = "Live API / web data"
      )
    )

    viz_type <- rdesk_prompt_choice(
      question = "What is the primary visualisation?",
      choices  = c(
        "charts"  = "Charts (ggplot2 plots)",
        "tables"  = "Data tables (summary + filtering)",
        "mixed"   = "Full dashboard (charts + tables + stats)"
      )
    )

    use_async_choice <- rdesk_prompt_choice(
      question = "Do you need background processing?",
      choices  = c(
        "yes" = "Yes - my computations take more than 1 second",
        "no"  = "No - keep it simple"
      )
    )
    use_async <- use_async_choice == "yes"

    theme <- rdesk_prompt_choice(
      question = "Colour theme?",
      choices  = c(
        "light"  = "Light",
        "dark"   = "Dark",
        "system" = "System default"
      )
    )
  } else {
    # Non-interactive defaults
    if (is.null(data_source)) data_source <- "builtin"
    if (is.null(viz_type))    viz_type    <- "mixed"
    if (is.null(use_async))   use_async   <- TRUE
  }

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


#' Internal prompt helper
#' @keywords internal
rdesk_prompt_choice <- function(question, choices) {
  cat(question, "\n")
  nms <- names(choices)
  for (i in seq_along(choices)) {
    cat(sprintf("  %d. %s\n", i, choices[i]))
  }
  repeat {
    cat("> ")
    input <- trimws(readLines(con = stdin(), n = 1, warn = FALSE))
    idx   <- suppressWarnings(as.integer(input))
    if (!is.na(idx) && idx >= 1 && idx <= length(choices)) {
      cat("\n")
      return(nms[idx])
    }
    # Also accept the key directly (e.g. "csv", "builtin")
    if (input %in% nms) {
      cat("\n")
      return(input)
    }
    cat("  Please enter a number between 1 and", length(choices), "\n")
  }
}


#' Internal success message
#' @keywords internal
rdesk_scaffold_success_msg <- function(name, app_dir, data_source, viz_type, use_async) {
  async_note <- if (use_async) "async() background processing" else "synchronous handlers"
  data_note  <- switch(data_source,
    builtin  = "mtcars built-in dataset",
    csv      = "CSV file loader with dialog",
    database = "DBI database connection template",
    api      = "httr2 API fetch template",
    "custom data source"
  )
  viz_note <- switch(viz_type,
    charts = "ggplot2 chart panel",
    tables = "sortable data table",
    mixed  = "full dashboard: charts + table + KPI cards",
    "visualization suite"
  )

  cat("\n[RDesk] Created:", app_dir, "\n")
  cat("[RDesk] Your app includes:\n")
  cat("  -", data_note, "\n")
  cat("  -", viz_note, "\n")
  cat("  -", async_note, "\n")
  cat("  - Native Win32 menu (File, Help)\n")
  cat("  - Loading overlay already wired up\n")
  cat("\n[RDesk] Run it now:\n")
  cat(sprintf("  setwd(\"%s\")\n", app_dir))
  cat("  source(\"app.R\")\n\n")
  cat("[RDesk] Build a distributable when ready:\n")
  cat(sprintf("  RDesk::build_app(app_dir = \"%s\", app_name = \"%s\")\n\n",
              app_dir, name))
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
  template_dir <- system.file("templates/scaffold", package = "RDesk")
  if (!nzchar(template_dir)) {
    template_dir <- file.path(find.package("RDesk"), "inst", "templates", "scaffold")
  }

  candidates <- c(
    if (!is.null(variant))
      file.path(template_dir, paste0(template_name, ".", variant)),
    file.path(template_dir, template_name)
  )

  template_path <- candidates[file.exists(candidates)][1]
  if (is.na(template_path)) {
    # One more try - maybe no variant extension?
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
