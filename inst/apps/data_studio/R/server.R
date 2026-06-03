# All on_message() handlers for Data Intelligence Studio


init_handlers <- function(app) {

  # ── App ready ────────────────────────────────────────────────────────
  app$on_ready(function() {

    app$set_menu(list(
      File = list(
        "Open file..."    = function() app$send("menu_open",   list()),
        "---",
        "Close dataset"   = function() app$send("close_data",  list()),
        "---",
        "Exit"            = app$quit
      ),
      Analysis = list(
        "Full profile"    = function() app$send("run_profile",  list()),
        "Correlation"     = function() app$send("run_corr",     list()),
        "Outlier scan"    = function() app$send("run_outliers", list()),
        "---",
        "Settings"        = function() app$send("open_settings", list())
      ),
      Export = list(
        "Export report (HTML)" = function() app$send("export_report", list()),
        "Export summary (CSV)" = function() app$send("export_csv",    list())
      ),
      Help = list(
        "Documentation"   = function() {
          utils::browseURL("https://janakiraman-311.github.io/RDesk/")
        },
        "About"           = function() {
          app$toast(
            "Data Intelligence Studio v1.0\nBuilt with RDesk",
            type = "info"
          )
        }
      )
    ))

    # Restore last preferences
    theme <- app$prefs$get("theme", default = "light")
    corr_method <- app$prefs$get("corr_method", default = "pearson")
    outlier_threshold <- app$prefs$get("outlier_threshold", default = "1.5")
    
    app$send("apply_preferences", list(
      theme = theme,
      corr_method = corr_method,
      outlier_threshold = outlier_threshold
    ))
    app$send("init_platform", list(os = .Platform$OS.type))
  })



  # ── Open file ────────────────────────────────────────────────────────
  app$on_message("open_file", function(payload) {

    # Use saved directory as starting point if available
    last_dir <- app$prefs$get("last_dir")

    path <- app$dialog_open(
      title   = "Open Dataset",
      filters = list(
        "Supported files (*.csv;*.rds)" = "*.csv;*.rds",
        "CSV files (*.csv)"             = "*.csv",
        "R data (*.rds)"                = "*.rds",
        "All files (*.*)"               = "*.*"
      )
    )

    if (is.null(path)) {
      app$send("open_file_result", list(cancelled = TRUE))
      return(invisible(NULL))
    }

    # Save directory for next time
    app$send("open_file_result", list(
      cancelled = FALSE,
      path      = path,
      filename  = basename(path)
    ))

    invisible(NULL)
  })

  # Menu-triggered open (same logic, called from File menu)
  app$on_message("menu_open", function(payload) {
    app$send("menu_open", list())
    invisible(NULL)
  })


  # ── Load and profile data ─────────────────────────────────────────────
  app$on_message("load_data", async(function(payload) {

    path <- payload$path
    ext  <- tolower(tools::file_ext(path))

    # Retrieve settings from payload
    corr_method <- if (!is.null(payload$settings$corr_method)) payload$settings$corr_method else "pearson"
    outlier_threshold <- if (!is.null(payload$settings$outlier_threshold)) as.numeric(payload$settings$outlier_threshold) else 1.5

    async_progress(5, message = "Reading file...")

    df <- tryCatch({
      if (ext == "csv") {
        utils::read.csv(path, stringsAsFactors = FALSE)
      } else if (ext == "rds") {
        result <- readRDS(path)
        if (!is.data.frame(result)) {
          stop("RDS file must contain a data frame.")
        }
        result
      } else {
        stop("Unsupported file type: ", ext)
      }
    }, error = function(e) {
      stop("Could not load file: ", e$message)
    })

    async_progress(20, message = "Computing overview...")
    overview <- profile_overview(df)

    async_progress(35, message = "Computing distributions...")
    dist_charts <- make_distribution_charts(df)

    async_progress(50, message = "Computing correlations...")
    corr_chart <- make_correlation_chart(df, method = corr_method)
    top_corr   <- get_top_correlations(df, n = 10, method = corr_method)

    async_progress(70, message = "Scanning for outliers...")
    outlier_table <- detect_outliers(df, threshold = outlier_threshold)
    outlier_chart <- make_outlier_chart(df, outlier_table)

    async_progress(85, message = "Analysing missing values...")
    missing_info <- profile_missing(df)
    preview_chart <- make_overview_chart(df, missing_info)

    async_progress(95, message = "Finalising...")

    list(
      overview        = overview,
      variable_summary = rdesk_df_to_list(profile_variables(df)),
      missing_info    = rdesk_df_to_list(missing_info),
      preview_chart   = preview_chart,
      dist_charts     = dist_charts,
      corr_chart      = corr_chart,
      top_corr        = rdesk_df_to_list(top_corr),
      outlier_table   = rdesk_df_to_list(outlier_table),
      outlier_chart   = outlier_chart,
      full_summary    = rdesk_df_to_list(profile_variables(df)),
      n_rows          = nrow(df),
      n_cols          = ncol(df),
      filename        = basename(path),
      path            = path
    )

  }, app = app, loading_message = "Loading and profiling dataset..."))

  # ── Load sample data ──────────────────────────────────────────────────
  app$on_message("load_sample", async(function(payload) {
    async_progress(10, message = "Generating synthetic data...")
    df <- generate_sample_data()

    # Retrieve settings from payload
    corr_method <- if (!is.null(payload$settings$corr_method)) payload$settings$corr_method else "pearson"
    outlier_threshold <- if (!is.null(payload$settings$outlier_threshold)) as.numeric(payload$settings$outlier_threshold) else 1.5

    async_progress(25, message = "Computing overview...")
    overview <- profile_overview(df)

    async_progress(40, message = "Computing distributions...")
    dist_charts <- make_distribution_charts(df)

    async_progress(55, message = "Computing correlations...")
    corr_chart <- make_correlation_chart(df, method = corr_method)
    top_corr   <- get_top_correlations(df, n = 10, method = corr_method)

    async_progress(70, message = "Scanning for outliers...")
    outlier_table <- detect_outliers(df, threshold = outlier_threshold)
    outlier_chart <- make_outlier_chart(df, outlier_table)

    async_progress(85, message = "Analysing missing values...")
    missing_info <- profile_missing(df)
    preview_chart <- make_overview_chart(df, missing_info)

    async_progress(95, message = "Finalising...")

    list(
      overview        = overview,
      variable_summary = rdesk_df_to_list(profile_variables(df)),
      missing_info    = rdesk_df_to_list(missing_info),
      preview_chart   = preview_chart,
      dist_charts     = dist_charts,
      corr_chart      = corr_chart,
      top_corr        = rdesk_df_to_list(top_corr),
      outlier_table   = rdesk_df_to_list(outlier_table),
      outlier_chart   = outlier_chart,
      full_summary    = rdesk_df_to_list(profile_variables(df)),
      n_rows          = nrow(df),
      n_cols          = ncol(df),
      filename        = "telecom_customer_churn.csv",
      path            = ""
    )
  }, app = app, loading_message = "Generating and profiling complex sample dataset..."))


  # ── Full profile ─────────────────────────────────────────────────────
  app$on_message("run_profile", async(function(payload) {

    df <- reconstruct_df_from_payload(payload$data)

    # Retrieve settings from payload
    corr_method <- if (!is.null(payload$settings$corr_method)) payload$settings$corr_method else "pearson"
    outlier_threshold <- if (!is.null(payload$settings$outlier_threshold)) as.numeric(payload$settings$outlier_threshold) else 1.5

    async_progress(10, message = "Computing distributions...")
    dist_charts <- make_distribution_charts(df)

    async_progress(30, message = "Computing correlations...")
    corr_chart <- make_correlation_chart(df, method = corr_method)
    top_corr   <- get_top_correlations(df, n = 10, method = corr_method)

    async_progress(60, message = "Scanning for outliers...")
    outlier_table <- detect_outliers(df, threshold = outlier_threshold)
    outlier_chart <- make_outlier_chart(df, outlier_table)

    async_progress(85, message = "Building summary...")
    full_summary  <- profile_variables(df)

    list(
      dist_charts   = dist_charts,
      corr_chart    = corr_chart,
      top_corr      = rdesk_df_to_list(top_corr),
      outlier_table = rdesk_df_to_list(outlier_table),
      outlier_chart = outlier_chart,
      full_summary  = rdesk_df_to_list(full_summary)
    )

  }, app = app, loading_message = "Profiling dataset..."))


  # ── Correlation analysis ─────────────────────────────────────────────
  app$on_message("run_corr", async(function(payload) {

    df         <- reconstruct_df_from_payload(payload$data)

    # Retrieve settings from payload
    corr_method <- if (!is.null(payload$settings$corr_method)) payload$settings$corr_method else "pearson"

    async_progress(30, message = "Computing correlation matrix...")
    corr_chart <- make_correlation_chart(df, method = corr_method)
    async_progress(80, message = "Extracting top correlations...")
    top_corr   <- get_top_correlations(df, n = 10, method = corr_method)

    list(
      corr_chart = corr_chart,
      top_corr   = rdesk_df_to_list(top_corr)
    )

  }, app = app, loading_message = "Computing correlations..."))


  # ── Outlier detection ────────────────────────────────────────────────
  app$on_message("run_outliers", async(function(payload) {

    df             <- reconstruct_df_from_payload(payload$data)

    # Retrieve settings from payload
    outlier_threshold <- if (!is.null(payload$settings$outlier_threshold)) as.numeric(payload$settings$outlier_threshold) else 1.5

    async_progress(40, message = "Scanning numeric columns...")
    outlier_table  <- detect_outliers(df, threshold = outlier_threshold)
    async_progress(75, message = "Generating outlier chart...")
    outlier_chart  <- make_outlier_chart(df, outlier_table)

    list(
      outlier_table = rdesk_df_to_list(outlier_table),
      outlier_chart = outlier_chart
    )

  }, app = app, loading_message = "Scanning for outliers..."))


  # ── Export ───────────────────────────────────────────────────────────
  app$on_message("export_report", function(payload) {

    path <- app$dialog_save(
      title   = "Export HTML Report",
      filters = list("HTML files (*.html)" = "*.html"),
      default = paste0(
        tools::file_path_sans_ext(payload$filename),
        "_report.html"
      )
    )

    if (is.null(path)) {
      app$send("export_report_result", list(cancelled = TRUE))
      return(invisible(NULL))
    }

    res <- tryCatch({
      generate_html_report(payload, path)
      list(cancelled = FALSE, saved_to = path)
    }, error = function(e) {
      list(cancelled = FALSE, error = e$message)
    })

    app$send("export_report_result", res)
    invisible(NULL)
  })

  app$on_message("export_csv", function(payload) {

    path <- app$dialog_save(
      title   = "Export Summary CSV",
      filters = list("CSV files (*.csv)" = "*.csv"),
      default = paste0(
        tools::file_path_sans_ext(payload$filename),
        "_summary.csv"
      )
    )

    if (is.null(path)) {
      app$send("export_csv_result", list(cancelled = TRUE))
      return(invisible(NULL))
    }

    summary_df <- reconstruct_df_from_rdesk_list(payload$variable_summary)
    res <- tryCatch({
      utils::write.csv(summary_df, path, row.names = FALSE)
      list(cancelled = FALSE, saved_to = path)
    }, error = function(e) {
      list(cancelled = FALSE, error = e$message)
    })

    app$send("export_csv_result", res)
    invisible(NULL)
  })


  # ── Preferences ──────────────────────────────────────────────────────
  app$on_message("save_pref", function(payload) {
    app$prefs$set(payload$key, payload$value)
    list(saved = TRUE)
  })

  app$on_message("get_pref", function(payload) {
    list(value = app$prefs$get(payload$key, default = payload$default))
  })


  # ── Close dataset ────────────────────────────────────────────────────
  app$on_message("close_data", function(payload) {
    list(closed = TRUE)
  })

  app$on_message("app_quit", function(payload) {
    app$quit()
    list(quit = TRUE)
  })

}



# Helper — reconstruct data frame from rdesk_df_to_list() output
reconstruct_df_from_rdesk_list <- function(lst) {
  if (is.null(lst) || length(lst$rows) == 0) return(data.frame())
  do.call(rbind, lapply(lst$rows, function(row) {
    as.data.frame(row, stringsAsFactors = FALSE)
  }))
}

# Helper — reconstruct df from JS payload
reconstruct_df_from_payload <- function(data) {
  if (is.null(data)) stop("No dataset loaded.")
  
  # If file path is available in the payload, load it directly (fast & reliable)
  if (!is.null(data$path) && nzchar(data$path)) {
    path <- data$path
    ext  <- tolower(tools::file_ext(path))
    df <- tryCatch({
      if (ext == "csv") {
        utils::read.csv(path, stringsAsFactors = FALSE)
      } else if (ext == "rds") {
        result <- readRDS(path)
        if (is.data.frame(result)) result else stop("RDS must be a data frame")
      } else {
        stop("Unsupported file extension: ", ext)
      }
    }, error = function(e) {
      stop("Failed to read dataset from '", path, "': ", e$message)
    })
    if (!is.null(df)) return(df)
  }
  
  # If it is the sample dataset, generate it on the fly
  if (!is.null(data$filename) && data$filename == "telecom_customer_churn.csv") {
    return(generate_sample_data())
  }
  
  stop("Dataset file path is empty and dataset is not the sample dataset.")
}
