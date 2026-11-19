# All IPC message handlers for Data Intelligence Studio
# Entry point: init_handlers(app) called by app.R

# ── Shared Dataset Loading & Profiling Helpers ──────────────────────────────

read_dataset_from_path <- function(path) {
  ext <- tolower(tools::file_ext(path))
  tryCatch({
    if (ext == "csv") {
      utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
    } else if (ext == "rds") {
      result <- readRDS(path)
      if (!is.data.frame(result)) {
        stop("RDS file must contain a data.frame.")
      }
      result
    } else {
      stop("Unsupported file type: .", ext, " (expected .csv or .rds)")
    }
  }, error = function(e) {
    stop("Could not load file: ", e$message)
  })
}

reconstruct_df_from_payload <- function(data) {
  if (is.null(data)) stop("No dataset loaded.")

  if (!is.null(data$path) && nzchar(as.character(data$path))) {
    return(read_dataset_from_path(as.character(data$path)))
  }

  if (!is.null(data$preset_id) && nzchar(as.character(data$preset_id))) {
    return(load_preset_dataset(as.character(data$preset_id)))
  }

  # Fallback for legacy filename-based identification
  if (!is.null(data$filename) && nzchar(as.character(data$filename))) {
    fname <- as.character(data$filename)
    if (grepl("pk_biomarker", fname, fixed = TRUE)) {
      return(load_preset_dataset("pk_biomarker"))
    }
    return(load_preset_dataset("cardio_trial"))
  }

  stop("Dataset source could not be resolved.")
}

reconstruct_df_from_rdesk_list <- function(lst) {
  if (is.null(lst) || is.null(lst$rows) || length(lst$rows) == 0L) {
    return(data.frame())
  }
  cols <- unlist(lst$cols)
  do.call(rbind, lapply(lst$rows, function(row) {
    vals <- lapply(cols, function(c) {
      v <- row[[c]]
      if (is.null(v) || length(v) == 0L) NA else v[[1L]]
    })
    names(vals) <- cols
    as.data.frame(vals, stringsAsFactors = FALSE, check.names = FALSE)
  }))
}

serialize_dist_stats <- function(ds) {
  if (is.null(ds)) return(NULL)
  list(
    variable         = ds$variable,
    group_by         = ds$group_by,
    n                = ds$n,
    n_missing        = ds$n_missing,
    mean             = ds$mean,
    sd               = ds$sd,
    median           = ds$median,
    q1               = ds$q1,
    q3               = ds$q3,
    iqr              = ds$iqr,
    min              = ds$min,
    max              = ds$max,
    skewness         = ds$skewness,
    shapiro_p        = ds$shapiro_p,
    shapiro_label    = ds$shapiro_label,
    normality_status = ds$normality_status,
    group_test       = ds$group_test,
    group_table      = rdesk_df_to_list(ds$group_table)
  )
}

build_full_profile_payload <- function(df,
                                       filename,
                                       path = "",
                                       preset_id = "",
                                       dataset_label = "",
                                       dataset_subtitle = "",
                                       corr_method = "pearson",
                                       outlier_threshold = 1.5,
                                       dist_var = NULL,
                                       group_by = NULL,
                                       plot_mode = "density",
                                       dark = FALSE,
                                       use_progress = FALSE) {
  if (use_progress) async_progress(20, message = "Profiling cohort schema & quality...")
  prof <- profile_dataset(
    df,
    corr_method       = corr_method,
    outlier_threshold = outlier_threshold,
    dist_var          = dist_var,
    group_by          = group_by
  )

  if (use_progress) async_progress(40, message = "Rendering completeness audit...")
  preview_chart <- chart_overview(df, missing_info = prof$missing, dark = dark)

  if (use_progress) async_progress(58, message = "Rendering variable distribution...")
  dist_chart <- chart_distributions(
    df,
    variable  = prof$default_var,
    group_by  = prof$default_group,
    plot_mode = plot_mode,
    dark      = dark
  )

  if (use_progress) async_progress(75, message = "Rendering correlation heatmap...")
  corr_chart <- chart_correlations(df, method = corr_method, dark = dark)

  if (use_progress) async_progress(90, message = "Rendering Tukey outlier diagnostics...")
  outlier_chart <- chart_outliers(
    df,
    outlier_table = prof$outliers,
    threshold     = outlier_threshold,
    dark          = dark
  )

  if (use_progress) async_progress(98, message = "Finalizing studio view...")

  list(
    overview         = prof$overview,
    variable_summary = rdesk_df_to_list(prof$variables),
    full_summary     = rdesk_df_to_list(prof$variables),
    missing_info     = rdesk_df_to_list(prof$missing),
    preview_chart    = preview_chart,
    dist_charts      = dist_chart,
    corr_chart       = corr_chart,
    top_corr         = rdesk_df_to_list(prof$correlations),
    outlier_table    = rdesk_df_to_list(prof$outliers),
    outlier_chart    = outlier_chart,
    numeric_vars     = as.list(prof$numeric_vars),
    categorical_vars = as.list(prof$categorical_vars),
    active_var       = prof$default_var,
    active_group     = prof$default_group,
    plot_mode        = plot_mode,
    dist_stats       = serialize_dist_stats(prof$dist_stats),
    subgroup_col     = prof$subgroup_col,
    subgroup_table   = rdesk_df_to_list(prof$subgroup_table),
    corr_method      = corr_method,
    outlier_threshold = outlier_threshold,
    n_rows           = nrow(df),
    n_cols           = ncol(df),
    filename         = filename,
    dataset_label    = if (nzchar(dataset_label)) dataset_label else filename,
    dataset_subtitle = dataset_subtitle,
    preset_id        = preset_id,
    path             = path
  )
}

# ── Main Handler Registration ───────────────────────────────────────────────

init_handlers <- function(app) {

  # In-memory cache on main R thread for instant interactive control updates
  state <- new.env(parent = emptyenv())
  state$df        <- NULL
  state$source_key <- ""

  get_active_df <- function(source_info) {
    path      <- if (!is.null(source_info$path)) as.character(source_info$path) else ""
    preset_id <- if (!is.null(source_info$preset_id)) as.character(source_info$preset_id) else ""
    key       <- paste0(preset_id, "|", path)

    if (!is.null(state$df) && identical(state$source_key, key)) {
      return(state$df)
    }

    df <- reconstruct_df_from_payload(source_info)
    state$df         <- df
    state$source_key <- key
    df
  }

  # Helper to read saved preferences with clean defaults
  read_prefs <- function() {
    list(
      theme             = as.character(app$prefs$get("theme", default = "light")),
      corr_method       = as.character(app$prefs$get("corr_method", default = "pearson")),
      outlier_threshold = as.numeric(app$prefs$get("outlier_threshold", default = "1.5"))
    )
  }

  # ── Native App Ready (Menu & Platform) ──────────────────────────────────
  app$on_ready(function() {
    app$set_menu(list(
      File = list(
        "Open CSV / RDS File..."       = function() app$send("menu_open", list()),
        "---",
        "Phase III Cardio-Metabolic"   = function() app$send("menu_preset", list(preset = "cardio_trial")),
        "PK & Biomarker Assay"         = function() app$send("menu_preset", list(preset = "pk_biomarker")),
        "---",
        "Close Dataset"                = function() app$send("close_data", list()),
        "---",
        "Exit"                         = app$quit
      ),
      Analysis = list(
        "Re-run Full Profile"          = function() app$send("run_profile", list()),
        "Correlation Matrix"           = function() app$send("run_corr", list()),
        "Outlier Quality Audit"        = function() app$send("run_outliers", list()),
        "---",
        "Preferences..."               = function() app$send("open_settings", list())
      ),
      Export = list(
        "Export HTML Report..."        = function() app$send("export_report", list()),
        "Export Variable Dictionary (CSV)..." = function() app$send("export_csv", list()),
        "Copy Summary Table to Clipboard"     = function() app$send("menu_copy_summary", list())
      ),
      Help = list(
        "RDesk Documentation"          = function() {
          utils::browseURL("https://janakiraman-311.github.io/RDesk/")
        },
        "About Data Intelligence Studio" = function() {
          app$toast(
            "Data Intelligence Studio — Clinical & Biostatistical Explorer (RDesk)",
            type = "info"
          )
        }
      )
    ))

    prefs <- read_prefs()
    app$send("apply_preferences", prefs)
    app$send("init_platform", list(os = .Platform$OS.type))
  })

  # ── Load Built-in Scientific Preset (Async) ─────────────────────────────
  load_preset_handler <- async(function(payload) {
    preset_id <- if (!is.null(payload$preset) && nzchar(as.character(payload$preset))) {
      as.character(payload$preset)
    } else {
      "cardio_trial"
    }
    meta <- get_preset_meta(preset_id)

    settings <- if (!is.null(payload$settings)) payload$settings else list()
    corr_method <- if (!is.null(settings$corr_method)) as.character(settings$corr_method) else "pearson"
    outlier_threshold <- if (!is.null(settings$outlier_threshold)) as.numeric(settings$outlier_threshold) else 1.5
    dark <- identical(settings$theme, "dark")

    async_progress(8, message = paste0("Generating ", meta$short_label, "..."))
    df <- load_preset_dataset(meta$id)

    build_full_profile_payload(
      df                = df,
      filename          = meta$filename,
      path              = "",
      preset_id         = meta$id,
      dataset_label     = meta$label,
      dataset_subtitle  = meta$subtitle,
      corr_method       = corr_method,
      outlier_threshold = outlier_threshold,
      plot_mode         = "density",
      dark              = dark,
      use_progress      = TRUE
    )
  }, app = app, loading_message = "Profiling clinical cohort...")

  app$on_message("load_preset", load_preset_handler)

  # Backwards-compatible sample trigger
  app$on_message("load_sample", async(function(payload) {
    meta <- get_preset_meta("cardio_trial")
    settings <- if (!is.null(payload$settings)) payload$settings else list()
    corr_method <- if (!is.null(settings$corr_method)) as.character(settings$corr_method) else "pearson"
    outlier_threshold <- if (!is.null(settings$outlier_threshold)) as.numeric(settings$outlier_threshold) else 1.5
    dark <- identical(settings$theme, "dark")

    async_progress(8, message = paste0("Generating ", meta$short_label, "..."))
    df <- load_preset_dataset("cardio_trial")

    build_full_profile_payload(
      df                = df,
      filename          = meta$filename,
      path              = "",
      preset_id         = meta$id,
      dataset_label     = meta$label,
      dataset_subtitle  = meta$subtitle,
      corr_method       = corr_method,
      outlier_threshold = outlier_threshold,
      plot_mode         = "density",
      dark              = dark,
      use_progress      = TRUE
    )
  }, app = app, loading_message = "Loading Phase III Clinical Trial Cohort..."))

  # ── Frontend Ready -> Auto-load Phase III Clinical Trial Cohort ─────────
  app$on_message("ready", function(payload) {
    prefs <- read_prefs()
    app$send("apply_preferences", prefs)

    # Pre-warm main-thread cache for instant interactive dropdowns
    state$df         <- load_preset_dataset("cardio_trial")
    state$source_key <- "cardio_trial|"

    load_preset_handler(list(
      preset   = "cardio_trial",
      settings = prefs
    ))
    invisible(NULL)
  })

  # ── Open Native File Dialog (CSV / RDS) ─────────────────────────────────
  app$on_message("open_file", function(payload) {
    path <- app$dialog_open(
      title   = "Open Clinical or Tabular Dataset",
      filters = list(
        "Supported datasets (*.csv;*.rds)" = "*.csv;*.rds",
        "CSV files (*.csv)"                = "*.csv",
        "R data files (*.rds)"             = "*.rds",
        "All files (*.*)"                  = "*.*"
      )
    )

    if (is.null(path)) {
      app$send("open_file_result", list(cancelled = TRUE))
      return(invisible(NULL))
    }

    app$prefs$set("last_dir", dirname(path))
    app$send("open_file_result", list(
      cancelled = FALSE,
      path      = path,
      filename  = basename(path)
    ))
    invisible(NULL)
  })

  app$on_message("menu_open", function(payload) {
    app$send("menu_open", list())
    invisible(NULL)
  })

  # ── Load & Profile User CSV/RDS File (Async) ────────────────────────────
  app$on_message("load_data", async(function(payload) {
    path <- as.character(payload$path)
    settings <- if (!is.null(payload$settings)) payload$settings else list()
    corr_method <- if (!is.null(settings$corr_method)) as.character(settings$corr_method) else "pearson"
    outlier_threshold <- if (!is.null(settings$outlier_threshold)) as.numeric(settings$outlier_threshold) else 1.5
    dark <- identical(settings$theme, "dark")

    async_progress(8, message = paste0("Reading ", basename(path), "..."))
    df <- read_dataset_from_path(path)

    build_full_profile_payload(
      df                = df,
      filename          = basename(path),
      path              = path,
      preset_id         = "",
      dataset_label     = basename(path),
      dataset_subtitle  = paste0("Local ", toupper(tools::file_ext(path)), " file"),
      corr_method       = corr_method,
      outlier_threshold = outlier_threshold,
      plot_mode         = "density",
      dark              = dark,
      use_progress      = TRUE
    )
  }, app = app, loading_message = "Loading and profiling dataset..."))

  # ── Full Re-Profile (Async) ─────────────────────────────────────────────
  app$on_message("run_profile", async(function(payload) {
    df <- reconstruct_df_from_payload(payload$data)
    settings <- if (!is.null(payload$settings)) payload$settings else list()
    corr_method <- if (!is.null(settings$corr_method)) as.character(settings$corr_method) else "pearson"
    outlier_threshold <- if (!is.null(settings$outlier_threshold)) as.numeric(settings$outlier_threshold) else 1.5
    dark <- identical(settings$theme, "dark")

    dist_var  <- if (!is.null(payload$dist_var)) as.character(payload$dist_var) else NULL
    group_by  <- if (!is.null(payload$group_by)) as.character(payload$group_by) else NULL
    plot_mode <- if (!is.null(payload$plot_mode)) as.character(payload$plot_mode) else "density"

    fname <- if (!is.null(payload$data$filename)) as.character(payload$data$filename) else "dataset"
    path  <- if (!is.null(payload$data$path)) as.character(payload$data$path) else ""
    pid   <- if (!is.null(payload$data$preset_id)) as.character(payload$data$preset_id) else ""
    lbl   <- if (!is.null(payload$data$dataset_label)) as.character(payload$data$dataset_label) else fname
    sub   <- if (!is.null(payload$data$dataset_subtitle)) as.character(payload$data$dataset_subtitle) else ""

    build_full_profile_payload(
      df                = df,
      filename          = fname,
      path              = path,
      preset_id         = pid,
      dataset_label     = lbl,
      dataset_subtitle  = sub,
      corr_method       = corr_method,
      outlier_threshold = outlier_threshold,
      dist_var          = dist_var,
      group_by          = group_by,
      plot_mode         = plot_mode,
      dark              = dark,
      use_progress      = TRUE
    )
  }, app = app, loading_message = "Re-running biostatistical profile..."))

  # ── Instant Interactive Panel Updates (Main Thread with Cached df) ──────

  app$on_message("update_distribution", function(payload) {
    res <- tryCatch({
      df        <- get_active_df(payload$source)
      variable  <- if (!is.null(payload$variable)) as.character(payload$variable) else NULL
      group_by  <- if (!is.null(payload$group_by)) as.character(payload$group_by) else ""
      plot_mode <- if (!is.null(payload$plot_mode)) as.character(payload$plot_mode) else "density"
      dark      <- identical(payload$theme, "dark")

      ds <- profile_distribution_stats(df, variable = variable, group_by = group_by)
      ch <- chart_distributions(
        df,
        variable  = ds$variable,
        group_by  = ds$group_by,
        plot_mode = plot_mode,
        dark      = dark
      )
      list(
        dist_charts = ch,
        dist_stats  = serialize_dist_stats(ds),
        active_var  = ds$variable,
        active_group = ds$group_by,
        plot_mode   = plot_mode
      )
    }, error = function(e) {
      list(error = e$message)
    })

    app$send("distribution_updated", res)
    invisible(NULL)
  })

  app$on_message("update_correlation", function(payload) {
    res <- tryCatch({
      df     <- get_active_df(payload$source)
      method <- if (!is.null(payload$corr_method)) as.character(payload$corr_method) else "pearson"
      dark   <- identical(payload$theme, "dark")

      app$prefs$set("corr_method", method)
      ch  <- chart_correlations(df, method = method, dark = dark)
      top <- get_top_correlations(df, n = 50L, method = method)
      list(
        corr_chart  = ch,
        top_corr    = rdesk_df_to_list(top),
        corr_method = method
      )
    }, error = function(e) {
      list(error = e$message)
    })

    app$send("correlation_updated", res)
    invisible(NULL)
  })

  app$on_message("update_outliers", function(payload) {
    res <- tryCatch({
      df        <- get_active_df(payload$source)
      threshold <- if (!is.null(payload$outlier_threshold)) as.numeric(payload$outlier_threshold) else 1.5
      dark      <- identical(payload$theme, "dark")

      app$prefs$set("outlier_threshold", as.character(threshold))
      tbl <- detect_outliers(df, threshold = threshold)
      ch  <- chart_outliers(df, outlier_table = tbl, threshold = threshold, dark = dark)
      list(
        outlier_table     = rdesk_df_to_list(tbl),
        outlier_chart     = ch,
        outlier_threshold = threshold,
        total_outliers    = as.integer(sum(tbl$n_outliers, na.rm = TRUE)),
        vars_with_outliers = as.integer(sum(tbl$n_outliers > 0, na.rm = TRUE))
      )
    }, error = function(e) {
      list(error = e$message)
    })

    app$send("outliers_updated", res)
    invisible(NULL)
  })

  app$on_message("update_subgroup", function(payload) {
    res <- tryCatch({
      df        <- get_active_df(payload$source)
      group_col <- if (!is.null(payload$group_col)) as.character(payload$group_col) else NULL
      sub_res   <- profile_subgroup_comparison(df, group_col = group_col)
      list(
        subgroup_col   = sub_res$group_col,
        subgroup_table = rdesk_df_to_list(sub_res$table)
      )
    }, error = function(e) {
      list(error = e$message)
    })

    app$send("subgroup_updated", res)
    invisible(NULL)
  })

  app$on_message("refresh_theme_charts", function(payload) {
    theme <- if (!is.null(payload$theme)) as.character(payload$theme) else "light"
    app$prefs$set("theme", theme)
    dark <- identical(theme, "dark")

    if (is.null(payload$source)) {
      return(invisible(NULL))
    }

    res <- tryCatch({
      df        <- get_active_df(payload$source)
      corr_m    <- if (!is.null(payload$corr_method)) as.character(payload$corr_method) else "pearson"
      out_th    <- if (!is.null(payload$outlier_threshold)) as.numeric(payload$outlier_threshold) else 1.5
      dist_var  <- if (!is.null(payload$variable)) as.character(payload$variable) else NULL
      group_by  <- if (!is.null(payload$group_by)) as.character(payload$group_by) else ""
      plot_mode <- if (!is.null(payload$plot_mode)) as.character(payload$plot_mode) else "density"

      list(
        preview_chart = chart_overview(df, dark = dark),
        dist_charts   = chart_distributions(df, variable = dist_var, group_by = group_by,
                                            plot_mode = plot_mode, dark = dark),
        corr_chart    = chart_correlations(df, method = corr_m, dark = dark),
        outlier_chart = chart_outliers(df, threshold = out_th, dark = dark)
      )
    }, error = function(e) {
      list(error = e$message)
    })

    app$send("theme_charts_updated", res)
    invisible(NULL)
  })

  # ── Clipboard Export (app$clipboard_write) ──────────────────────────────
  app$on_message("copy_summary", function(payload) {
    target <- if (!is.null(payload$target)) as.character(payload$target) else "variables"
    tsv <- ""

    if (!is.null(payload$table_data)) {
      tsv <- format_table_tsv(payload$table_data)
    } else if (!is.null(payload$source)) {
      df <- tryCatch(get_active_df(payload$source), error = function(e) NULL)
      if (!is.null(df)) {
        if (identical(target, "subgroup")) {
          sub <- profile_subgroup_comparison(df, group_col = payload$group_col)
          tsv <- format_table_tsv(sub$table)
        } else {
          tsv <- format_table_tsv(profile_variables(df))
        }
      }
    }

    if (!nzchar(tsv)) {
      app$toast("No summary table available to copy.", type = "warning")
      app$send("copy_summary_result", list(ok = FALSE))
      return(invisible(NULL))
    }

    app$clipboard_write(tsv)
    lbl <- if (identical(target, "subgroup")) "Subgroup comparison table" else "Variable summary table"
    app$toast(paste0(lbl, " copied to clipboard (TSV)"), type = "success")
    app$send("copy_summary_result", list(ok = TRUE, target = target))
    invisible(NULL)
  })

  # ── Menu-Triggered Correlation & Outlier Async Runners ──────────────────
  app$on_message("run_corr", async(function(payload) {
    df <- reconstruct_df_from_payload(payload$data)
    settings <- if (!is.null(payload$settings)) payload$settings else list()
    corr_method <- if (!is.null(settings$corr_method)) as.character(settings$corr_method) else "pearson"
    dark <- identical(settings$theme, "dark")

    async_progress(35, message = "Computing correlation matrix...")
    corr_chart <- chart_correlations(df, method = corr_method, dark = dark)
    async_progress(80, message = "Computing confidence intervals & p-values...")
    top_corr   <- get_top_correlations(df, n = 50L, method = corr_method)

    list(
      corr_chart  = corr_chart,
      top_corr    = rdesk_df_to_list(top_corr),
      corr_method = corr_method
    )
  }, app = app, loading_message = "Computing correlations..."))

  app$on_message("run_outliers", async(function(payload) {
    df <- reconstruct_df_from_payload(payload$data)
    settings <- if (!is.null(payload$settings)) payload$settings else list()
    outlier_threshold <- if (!is.null(settings$outlier_threshold)) as.numeric(settings$outlier_threshold) else 1.5
    dark <- identical(settings$theme, "dark")

    async_progress(40, message = "Scanning numeric variables...")
    outlier_table <- detect_outliers(df, threshold = outlier_threshold)
    async_progress(75, message = "Rendering Tukey IQR diagnostics...")
    outlier_chart <- chart_outliers(df, outlier_table = outlier_table,
                                    threshold = outlier_threshold, dark = dark)

    list(
      outlier_table     = rdesk_df_to_list(outlier_table),
      outlier_chart     = outlier_chart,
      outlier_threshold = outlier_threshold
    )
  }, app = app, loading_message = "Scanning for outliers..."))

  # ── File Exports (HTML Report & Summary CSV) ────────────────────────────
  app$on_message("export_report", function(payload) {
    fname <- if (!is.null(payload$filename) && nzchar(payload$filename)) {
      payload$filename
    } else {
      "clinical_profile"
    }

    path <- app$dialog_save(
      title   = "Export Clinical Profile Report (HTML)",
      filters = list("HTML files (*.html)" = "*.html"),
      default = paste0(tools::file_path_sans_ext(fname), "_report.html")
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
    fname <- if (!is.null(payload$filename) && nzchar(payload$filename)) {
      payload$filename
    } else {
      "clinical_summary"
    }

    path <- app$dialog_save(
      title   = "Export Variable Dictionary (CSV)",
      filters = list("CSV files (*.csv)" = "*.csv"),
      default = paste0(tools::file_path_sans_ext(fname), "_dictionary.csv")
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

  # ── Preferences & Lifecycle ─────────────────────────────────────────────
  app$on_message("save_pref", function(payload) {
    app$prefs$set(payload$key, payload$value)
    invisible(NULL)
  })

  app$on_message("get_pref", function(payload) {
    val <- app$prefs$get(payload$key, default = payload$default)
    app$send("get_pref_result", list(key = payload$key, value = val))
    invisible(NULL)
  })

  app$on_message("close_data", function(payload) {
    state$df         <- NULL
    state$source_key <- ""
    invisible(NULL)
  })

  app$on_message("app_quit", function(payload) {
    app$quit()
    invisible(NULL)
  })
}

# Compatibility alias
register_handlers <- function(app, state = NULL) {
  init_handlers(app)
}
