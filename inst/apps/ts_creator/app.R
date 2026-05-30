# Standardize path: resolve the app directory from the running script whenever possible
resolve_app_dir <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    script_path <- normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/", mustWork = FALSE)
    if (nzchar(script_path) && file.exists(script_path)) {
      return(dirname(script_path))
    }
  }

  if (!nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    rstudio_path <- tryCatch(rstudioapi::getActiveDocumentContext()$path, error = function(e) "")
    if (nzchar(rstudio_path) && file.exists(rstudio_path)) {
      return(dirname(normalizePath(rstudio_path, winslash = "/", mustWork = TRUE)))
    }
  }

  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
}

app_dir <- resolve_app_dir()

# Development Guard
pkg_root <- dirname(dirname(dirname(app_dir)))
is_dev <- file.exists(file.path(pkg_root, "DESCRIPTION")) &&
  file.exists(file.path(pkg_root, "R", "App.R"))

if (!nzchar(Sys.getenv("R_BUNDLE_APP")) && is_dev) {
  message("[RDesk] Dev mode detected. Loading local source...")
  devtools::load_all(pkg_root)
} else {
  suppressPackageStartupMessages(library(RDesk))
}

suppressPackageStartupMessages(library(haven))
suppressPackageStartupMessages(library(Hmisc))
suppressPackageStartupMessages(library(dplyr))

# Handle startup logging for bundled apps
if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
  app_name <- Sys.getenv("R_APP_NAME", "TSCreator")
  log_dir <- RDesk:::rdesk_log_dir(app_name)
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)

  log_file <- file.path(log_dir, "rdesk_startup.log")
  sink_conn <- file(log_file, open = "wt")
  sink(sink_conn, type = "message")

  cat(sprintf("[%s] RDesk startup initiated (TS Creator)\n", Sys.time()))
  cat("R Version:", R.version.string, "\n")
  cat("libPaths:\n")
  cat(paste("  -", .libPaths(), collapse = "\n"), "\n\n")
}

cleanup_bundle_logging <- function() {
  if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    if (sink.number(type = "message") > 0) sink(type = "message")
    if (exists("sink_conn", inherits = FALSE) && isOpen(sink_conn)) close(sink_conn)
  }
}
on.exit(cleanup_bundle_logging(), add = TRUE)

tryCatch({
  app <- App$new(
    title = "TS Domain Creator (Native)",
    width = 1100,
    height = 800,
    www = file.path(app_dir, "www")
  )

  # Enable hot reload in development mode!
  if (is_dev && !nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    rdesk_watch(app)
  }

  const_parmCD <- "STSTDTC"
  const_filename <- "ts.xpt"

  # Initial data dispatch on startup - populate saved inputs!
  app$on_ready(function() {
    saved_study_id <- app$prefs$get("study_id", "")
    saved_dir <- app$recent$get("export_dir", "C:/Test")
    app$send("init_inputs", list(study_id = saved_study_id, directory = saved_dir))
  })

  app$on_message("pick_folder", function(payload) {
    path <- app$dialog_open("Select Export Directory")
    if (!is.null(path)) {
      dir_path <- dirname(path)
      app$send("update_folder", list(path = dir_path))
    }
  })

  # Asynchronous export with real-time progress reporting!
  app$on_message("export", async(function(input) {
    if (is.null(input$studyID) || trimws(input$studyID) == "") {
      stop("Study ID is mandatory.")
    }

    selected_directory <- input$directoryPath
    if (is.null(selected_directory) || selected_directory == "") {
      stop("Invalid directory path.")
    }

    # Step 1: Initialize directory
    RDesk::async_progress(10, "Validating output directory...")
    Sys.sleep(0.4)
    if (!dir.exists(selected_directory)) {
      tryCatch(dir.create(selected_directory, recursive = TRUE), error = function(e) {})
    }

    # Step 2: Prepare transport data structure
    RDesk::async_progress(40, "Preparing SAS transport metadata...")
    Sys.sleep(0.4)
    full_file_path <- file.path(selected_directory, const_filename)

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

    Hmisc::label(data) <- "Trial Summary"
    Hmisc::label(data[["STUDYID"]]) <- "Study Identifier"
    Hmisc::label(data[["TSPARMCD"]]) <- "Trial Summary Parameter Short Name"
    Hmisc::label(data[["TSVAL"]]) <- "Parameter Value"
    Hmisc::label(data[["TSVALNF"]]) <- "Parameter Null Flavor"

    # Step 3: Write xpt file
    RDesk::async_progress(70, "Writing SAS Version 5 XPT file...")
    Sys.sleep(0.4)
    haven::write_xpt(data, path = full_file_path, version = 5)

    # Step 4: Finalize metadata
    RDesk::async_progress(95, "Reading metadata for validation...")
    Sys.sleep(0.3)
    info <- file.info(full_file_path)
    info_str <- paste(
      "File Size: ", info$size, " bytes\n",
      "Last Modified: ", info$mtime, "\n",
      "Source: ", full_file_path
    )

    table_html <- paste0(
      '<table class="w-full text-sm text-left text-slate-500 border-collapse">',
      '<thead class="text-xs text-slate-700 uppercase bg-slate-50 border-b">',
      '<tr><th class="px-4 py-2">STUDYID</th><th class="px-4 py-2">TSPARMCD</th><th class="px-4 py-2">TSVAL</th><th class="px-4 py-2">TSVALNF</th></tr>',
      "</thead><tbody>",
      "<tr>",
      '<td class="px-4 py-3 border-b">', data$STUDYID, "</td>",
      '<td class="px-4 py-3 border-b">', data$TSPARMCD, "</td>",
      '<td class="px-4 py-3 border-b">', data$TSVAL, "</td>",
      '<td class="px-4 py-3 border-b">', data$TSVALNF, "</td>",
      "</tr>",
      "</tbody></table>"
    )

    list(
      info = info_str,
      table_html = table_html,
      study_id = input$studyID,
      export_dir = selected_directory
    )
  }, app = app, loading_message = "Exporting data..."))

  # Register a post-export callback to persist settings in main thread!
  app$on_message("export_result", function(payload) {
    if (!is.null(payload$study_id)) {
      app$prefs$set("study_id", payload$study_id)
    }
    if (!is.null(payload$export_dir)) {
      app$recent$set("export_dir", payload$export_dir)
    }
    app$send("results", payload)
  })

  app$run()

}, error = function(e) {
  if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
    cat(sprintf("\n[%s] CRITICAL ERROR:\n%s\n", Sys.time(), e$message))
  }
  stop(e)
})
