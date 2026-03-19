# Standardize path for RDesk
script_dir <- getwd()

# Development Guard
pkg_root <- dirname(dirname(dirname(script_dir)))
is_dev <- file.exists(file.path(pkg_root, "DESCRIPTION")) && 
          file.exists(file.path(pkg_root, "R", "App.R"))

if (!nzchar(Sys.getenv("R_BUNDLE_APP")) && is_dev) {
  message("[RDesk] Dev mode detected. Loading local source...")
  devtools::load_all(pkg_root)
} else {
  library(RDesk)
}

library(haven)
library(Hmisc)
library(dplyr)

# Handle startup logging for bundled apps
if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
  app_name <- Sys.getenv("R_APP_NAME", "RDeskApp")
  log_dir <- file.path(Sys.getenv("LOCALAPPDATA"), "RDesk", app_name)
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
  
  log_file <- file.path(log_dir, "rdesk_startup.log")
  sink_conn <- file(log_file, open = "wt")
  sink(sink_conn, type = "message")
  sink(sink_conn, type = "output")
  
  # Log environment details
  cat(sprintf("[%s] RDesk startup initiated (TS Creator)\n", Sys.time()))
  cat("R Version:", R.version.string, "\n")
  cat("libPaths:\n")
  cat(paste("  -", .libPaths(), collapse = "\n"), "\n\n")
}

tryCatch({
  app <- App$new(
    title = "TS Domain Creator (Native)",
    width = 1100,
    height = 800,
    www   = "www"
  )

  # Constants
  const_parmCD <- "STSTDTC"
  const_filename <- "ts.xpt"

  # --- IPC Handlers (The "Server" logic) ---

  # 1. Folder Selection (New Native feature!)
  app$on_message("pick_folder", function(payload) {
    path <- app$dialog_open("Select Export Directory")
    if (!is.null(path)) {
      dir_path <- dirname(path)
      app$send("update_folder", list(path = dir_path))
    }
  })

  # 2. Export logic
  app$on_message("export", function(input) {
    
    # Validation
    if (is.null(input$studyID) || trimws(input$studyID) == "") {
      app$toast("Error: Study ID is mandatory.", type = "error")
      return()
    }
    
    selected_directory <- input$directoryPath
    if (is.null(selected_directory) || selected_directory == "") {
      app$toast("Error: Invalid directory path.", type = "error")
      return()
    }
    
    app$loading_start("Generating TS domain...")
    
    # Ensure directory exists locally
    if (!dir.exists(selected_directory)) {
      tryCatch(dir.create(selected_directory, recursive = TRUE), error = function(e) {})
    }
    
    full_file_path <- file.path(selected_directory, const_filename)
    
    # Data logic (Exact copy from Shiny)
    ts_val <- ""
    ts_val_nf <- "NA"
    
    if (input$useDate && !is.null(input$studyDate) && input$studyDate != "") {
      ts_val <- input$studyDate 
      ts_val_nf <- ""
    }
    
    data <- data.frame(
      STUDYID = input$studyID,
      TSPARMCD = const_parmCD,
      TSVAL = ts_val,
      TSVALNF = ts_val_nf,
      stringsAsFactors = FALSE
    )
    
    # Add labels
    label(data) <- 'Trial Summary'
    label(data[['STUDYID']]) <- 'Study Identifier'
    label(data[['TSPARMCD']]) <- 'Trial Summary Parameter Short Name'
    label(data[['TSVAL']]) <- 'Parameter Value'
    label(data[['TSVALNF']]) <- 'Parameter Null Flavor'
    
    # Write to XPT
    write_xpt(data, path = full_file_path, version = 5)
    
    # Success
    app$loading_done()
    app$toast("Export successful!", type = "success")
    
    # --- UI Refresh logic ---
    
    # File Info
    info <- file.info(full_file_path)
    info_str <- paste(
      "File Size: ", info$size, " bytes\n",
      "Last Modified: ", info$mtime, "\n",
      "Source: ", full_file_path
    )
    
    # HTML Table generator
    table_html <- paste0(
      '<table class="w-full text-sm text-left text-slate-500 border-collapse">',
      '<thead class="text-xs text-slate-700 uppercase bg-slate-50 border-b">',
      '<tr><th class="px-4 py-2">STUDYID</th><th class="px-4 py-2">TSPARMCD</th><th class="px-4 py-2">TSVAL</th><th class="px-4 py-2">TSVALNF</th></tr>',
      '</thead><tbody>',
      '<tr>',
      '<td class="px-4 py-3 border-b">', data$STUDYID, '</td>',
      '<td class="px-4 py-3 border-b">', data$TSPARMCD, '</td>',
      '<td class="px-4 py-3 border-b">', data$TSVAL, '</td>',
      '<td class="px-4 py-3 border-b">', data$TSVALNF, '</td>',
      '</tr>',
      '</tbody></table>'
    )
    
    # Send everything to UI
    app$send("results", list(
      info = info_str,
      table_html = table_html
    ))
  })

  # Run the app
  app$run()

}, error = function(e) {
  if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    cat(sprintf("\n[%s] CRITICAL ERROR:\n%s\n", Sys.time(), e$message))
    sink()
    sink()
  }
  stop(e)
})
