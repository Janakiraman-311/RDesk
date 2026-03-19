#' Create a new RDesk application project
#'
#' @param app_name Name of the application
#' @param path Directory where the project will be created
#' @export
rdesk_create_app <- function(app_name, path = ".") {
  path <- path.expand(path)
  if (path == ".") {
    path <- getwd()
  }
  target_dir <- file.path(path, app_name)
  
  if (dir.exists(target_dir)) {
    stop("[RDesk] Directory already exists: ", target_dir)
  }
  
  message("[RDesk] Creating new project: ", app_name)
  dir.create(target_dir, recursive = TRUE)
  
  # Create structure
  dirs <- c("R", "www", "www/css", "www/js", "tests")
  for (d in dirs) {
    dir.create(file.path(target_dir, d), recursive = TRUE)
  }
  
  # 1. app.R (Thin Entry Point)
  writeLines(c(
    paste0("# ", app_name, " entry point"),
    "library(RDesk)",
    "",
    "# Source all modular logic",
    "if (dir.exists('R')) {",
    "  lapply(list.files('R', pattern = '\\\\.R$', full.names = TRUE), source)",
    "}",
    "",
    "if (nzchar(Sys.getenv('R_BUNDLE_APP'))) {",
    "  # Logging for bundled apps",
    "  app_name <- Sys.getenv('R_APP_NAME', 'RDeskApp')",
    "  log_dir <- RDesk:::rdesk_log_dir(app_name)",
    "  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)",
    "  log_file <- file.path(log_dir, 'rdesk_startup.log')",
    "  sink_conn <- file(log_file, open = 'wt')",
    "  sink(sink_conn, type = 'message')",
    "}",
    "",
    "tryCatch({",
    "  # Start the app",
    paste0("  app <- RDesk::App$new(\"", app_name, "\", width = 1000, height = 700)"),
    "  ",
    "  # Define handlers (usually in R/server.R)",
    "  if (exists('init_handlers')) init_handlers(app)",
    "  ",
    "  app$run()",
    "}, error = function(e) {",
    "  if (nzchar(Sys.getenv('R_BUNDLE_APP'))) {",
    "    cat(sprintf('\\n[%s] CRITICAL ERROR:\\n%s\\n', Sys.time(), e$message))",
    "    if (sink.number(type = 'message') > 0) sink(type = 'message')",
    "    if (exists('sink_conn')) close(sink_conn)",
    "  }",
    "  stop(e)",
    "})"
  ), file.path(target_dir, "app.R"))
  
  # 2. R/server.R
  writeLines(c(
    "# Message handlers and UI events",
    "init_handlers <- function(app) {",
    "  app$on_message('ready', function(msg) {",
    "    app$notify('Hello!', 'Welcome to your new RDesk app.')",
    "    if (exists('prepare_initial_data')) {",
    "       data <- prepare_initial_data()",
    "       app$send('init_data', data)",
    "    }",
    "  })",
    "  ",
    "  app$on_message('click_action', function(msg) {",
    "    app$notify('Action!', 'User clicked a button.')",
    "  })",
    "}"
  ), file.path(target_dir, "R", "server.R"))
  
  # 3. R/data.R
  writeLines(c(
    "# Data processing logic",
    "prepare_initial_data <- function() {",
    "  list(",
    "    message = \"RDesk is connected.\",",
    "    timestamp = as.character(Sys.time())",
    "  )",
    "}"
  ), file.path(target_dir, "R", "data.R"))
  
  # 4. R/plots.R
  writeLines(c(
    "# Visualization logic",
    "render_sample_plot <- function() {",
    "  if (!requireNamespace('ggplot2', quietly = TRUE)) {",
    "    stop('Package \"ggplot2\" is required for render_sample_plot().')",
    "  }",
    "  ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) +",
    "    ggplot2::geom_point() +",
    "    ggplot2::theme_minimal()",
    "}"
  ), file.path(target_dir, "R", "plots.R"))
  
  # 5. www/index.html
  writeLines(c(
    "<!DOCTYPE html>",
    "<html>",
    "<head>",
    "    <title>New RDesk App</title>",
    "    <link rel='stylesheet' href='css/style.css'>",
    "</head>",
    "<body>",
    "    <div id='app-root'>",
    "        <h1>Welcome to RDesk</h1>",
    "        <p id='status'>Connecting to R...</p>",
    "        <button onclick='window.RDesk.send(\"click_action\", {})'>Click Me</button>",
    "    </div>",
    "    ",
    "    <!-- RDesk Core JS (Injected by server, but we shim for dev) -->",
    "    <script src='js/app.js'></script>",
    "</body>",
    "</html>"
  ), file.path(target_dir, "www", "index.html"))
  
  # 6. www/css/style.css
  writeLines(c(
    "body {",
    "    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;",
    "    background: #f4f7f6;",
    "    display: flex;",
    "    justify-content: center;",
    "    align-items: center;",
    "    height: 100vh;",
    "    margin: 0;",
    "}",
    "#app-root {",
    "    background: white;",
    "    padding: 2rem;",
    "    border-radius: 8px;",
    "    box-shadow: 0 4px 6px rgba(0,0,0,0.1);",
    "    text-align: center;",
    "}"
  ), file.path(target_dir, "www", "css", "style.css"))
  
  # 7. www/js/app.js
  writeLines(c(
    "// Wait for RDesk to be ready",
    "window.addEventListener('rdesk-ready', () => {",
    "    document.getElementById('status').innerText = 'Connected to R!';",
    "    ",
    "    window.RDesk.on('init_data', (data) => {",
    "       console.log('Received data:', data);",
    "    });",
    "});",
    "",
    "// Simple polyfill for development",
    "if (!window.RDesk) {",
    "   console.log('RDesk JS Bridge not detected yet...');",
    "}"
  ), file.path(target_dir, "www", "js", "app.js"))
  
  # 8. DESCRIPTION
  writeLines(c(
    paste0("Package: ", app_name),
    "Title: New RDesk Application",
    "Version: 1.0.0",
    "RDeskVersion: 0.1.0",
    "Depends: ggplot2, dplyr",
    "Description: Generated by RDesk scaffolding."
  ), file.path(target_dir, "DESCRIPTION"))
  
  # 9. tests/test-data.R
  writeLines(c(
    "library(testthat)",
    "",
    "test_that('Data preparation works', {",
    "  expect_type(prepare_initial_data(), 'list')",
    "})"
  ), file.path(target_dir, "tests", "test-data.R"))

  message("[RDesk] Project structure created:")
  if (requireNamespace("fs", quietly = TRUE)) {
    fs::dir_tree(target_dir)
  } else {
    message(" (Folder structure created at ", target_dir, ")")
  }
  
  cat("\nNext Steps:\n")
  cat("1. Open app.R and customize handlers.\n")
  cat("2. Run RDesk::build_app(app_dir = \"", target_dir, "\") to create an installer.\n")
}
