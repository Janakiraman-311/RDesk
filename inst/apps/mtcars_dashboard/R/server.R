# inst/apps/mtcars_dashboard/R/server.R
# Message handlers, asynchronous OLS regression workbench, clipboard & native exports

ALLOWED_X_VARS     <- c("wt", "hp", "disp", "drat", "qsec")
ALLOWED_Y_VARS     <- c("mpg", "qsec", "hp", "wt")
ALLOWED_PLOT_TYPES <- c("scatter", "boxplot", "density", "efficiency")
ALLOWED_SMOOTH     <- c("lm", "loess")
ALLOWED_RESPONSES  <- c("mpg", "qsec")
ALLOWED_PREDICTORS <- c("wt", "hp", "cyl", "disp", "am", "gear", "drat")

build_explorer_payload <- function(env) {
  df <- env$filtered
  list(
    kpis    = kpis(df, total_n = nrow(env$df)),
    chart   = plot_to_b64(make_plot(df, env$x_var, env$y_var, env$plot_type, env$smooth_method)),
    summary = summary_stats(df),
    table   = fleet_table(df),
    state   = list(
      x_var         = env$x_var,
      y_var         = env$y_var,
      plot_type     = env$plot_type,
      smooth_method = env$smooth_method,
      cyl_filter    = I(as.numeric(env$cyl_filter)),
      am_filter     = env$am_filter,
      hp_min        = env$hp_min,
      hp_max        = env$hp_max
    )
  )
}

push_update <- function(app, env) {
  app$send("data_update", build_explorer_payload(env))
}

fit_regression_model <- function(payload, progress_cb = NULL) {
  report_progress <- function(pct, msg) {
    if (is.function(progress_cb)) progress_cb(pct, msg)
  }

  report_progress(15, "Preparing telemetry matrix and validating predictors...")

  response <- as.character(if (is.null(payload$response)) "mpg" else payload$response)
  if (!response %in% ALLOWED_RESPONSES) response <- "mpg"

  raw_preds <- as.character(unlist(payload$predictors))
  preds <- intersect(unique(raw_preds), ALLOWED_PREDICTORS)
  preds <- setdiff(preds, response)

  include_interaction <- isTRUE(payload$interaction)
  if (include_interaction) {
    preds <- unique(c(preds, "wt", "hp"))
    preds <- setdiff(preds, response)
  }

  if (length(preds) == 0) {
    stop("Select at least one predictor variable before running regression.")
  }

  df <- build_fleet_df()
  scope <- as.character(if (is.null(payload$scope)) "all" else payload$scope)
  if (identical(scope, "filtered")) {
    cyls   <- if (is.null(payload$cyls)) c(4, 6, 8) else as.numeric(unlist(payload$cyls))
    am     <- if (is.null(payload$am)) "all" else as.character(payload$am)
    hp_min <- if (is.null(payload$hp_min)) min(df$hp) else as.numeric(payload$hp_min)
    hp_max <- if (is.null(payload$hp_max)) max(df$hp) else as.numeric(payload$hp_max)
    df <- filter_fleet(df, cyl_filter = cyls, am_filter = am, hp_min = hp_min, hp_max = hp_max)
    scope_label <- "Filtered Fleet"
  } else {
    scope_label <- "Full Fleet (Motor Trend 1974)"
  }

  rhs_terms <- preds
  if (include_interaction && all(c("wt", "hp") %in% preds)) {
    rhs_terms <- c(rhs_terms, "wt:hp")
  }
  formula_str <- paste(response, "~", paste(rhs_terms, collapse = " + "))

  min_rows <- length(rhs_terms) + 3L
  if (nrow(df) < min_rows) {
    stop(sprintf(
      "Insufficient observations (n = %d) for %d model terms. Broaden fleet filters or reduce predictors.",
      nrow(df), length(rhs_terms)
    ))
  }

  report_progress(42, paste0("Fitting OLS model: ", formula_str))
  Sys.sleep(0.18)

  model <- stats::lm(stats::as.formula(formula_str), data = df)

  report_progress(68, "Computing tidy coefficients (95% CI) & fit diagnostics...")
  Sys.sleep(0.15)

  tidy_df <- broom::tidy(model, conf.int = TRUE, conf.level = 0.95)
  glance_df <- broom::glance(model)
  aug_df <- broom::augment(model, data = df)

  coef_df <- data.frame(
    term      = as.character(tidy_df$term),
    estimate  = round(as.numeric(tidy_df$estimate), 4),
    std_error = round(as.numeric(tidy_df$std.error), 4),
    statistic = round(as.numeric(tidy_df$statistic), 3),
    p_value   = as.numeric(tidy_df$p.value),
    conf_low  = round(as.numeric(tidy_df$conf.low), 4),
    conf_high = round(as.numeric(tidy_df$conf.high), 4),
    sig       = sig_stars(as.numeric(tidy_df$p.value)),
    stringsAsFactors = FALSE
  )

  metrics <- list(
    r_squared     = round(as.numeric(glance_df$r.squared[1]), 4),
    adj_r_squared = round(as.numeric(glance_df$adj.r.squared[1]), 4),
    f_statistic   = round(as.numeric(glance_df$statistic[1]), 2),
    f_p_value     = as.numeric(glance_df$p.value[1]),
    aic           = round(as.numeric(glance_df$AIC[1]), 2),
    rse           = round(as.numeric(glance_df$sigma[1]), 4)
  )

  nobs     <- as.integer(glance_df$nobs[1])
  df_resid <- as.integer(glance_df$df.residual[1])

  report_progress(88, "Rendering Actual vs. Predicted and Residuals diagnostics...")

  p_actual <- make_actual_vs_pred_plot(aug_df, response, formula_str)
  p_resid  <- make_residuals_plot(aug_df, response, rse = metrics$rse)

  summary_text <- build_model_summary_text(
    formula_str = formula_str,
    scope_label = scope_label,
    nobs        = nobs,
    df_resid    = df_resid,
    metrics     = metrics,
    coef_df     = coef_df
  )

  markdown_section <- build_model_markdown_section(
    formula_str = formula_str,
    scope_label = scope_label,
    nobs        = nobs,
    df_resid    = df_resid,
    metrics     = metrics,
    coef_df     = coef_df
  )

  report_progress(100, "Diagnostics complete.")

  list(
    formula          = formula_str,
    response         = response,
    scope            = scope,
    scope_label      = scope_label,
    nobs             = nobs,
    df_residual      = df_resid,
    metrics          = metrics,
    coefficients     = coef_df,
    plot_actual_pred = plot_to_b64(p_actual, w = 520, h = 340, dpi = 120),
    plot_residuals   = plot_to_b64(p_resid,  w = 520, h = 340, dpi = 120),
    summary_text     = summary_text,
    markdown_section = markdown_section
  )
}

init_handlers <- function(app, env) {
  # -- navigation -----------------------------------------------------------
  app$on_message("nav", function(msg) {
    app$send("switch_section", list(section = msg$target))
  })

  # -- explorer initialization ----------------------------------------------
  app$on_message("ready", function(msg) {
    saved_plot <- app$recent$get("plot_type", "scatter")
    saved_x    <- app$recent$get("x_var", "wt")
    saved_y    <- app$recent$get("y_var", "mpg")

    if (saved_plot %in% ALLOWED_PLOT_TYPES) env$plot_type <- saved_plot
    if (saved_x %in% ALLOWED_X_VARS)        env$x_var     <- saved_x
    if (saved_y %in% ALLOWED_Y_VARS)        env$y_var     <- saved_y

    apply_filters(env)
    push_update(app, env)

    app$send("init_ui_state", list(
      plot_type     = env$plot_type,
      x_var         = env$x_var,
      y_var         = env$y_var,
      smooth_method = env$smooth_method,
      cyl_filter    = I(as.numeric(env$cyl_filter)),
      am_filter     = env$am_filter,
      hp_min        = env$hp_min,
      hp_max        = env$hp_max,
      hp_bounds     = list(
        min = min(env$df$hp, na.rm = TRUE),
        max = max(env$df$hp, na.rm = TRUE)
      )
    ))
  })

  # -- unified interactive filter & plot controls ---------------------------
  app$on_message("update_filters", function(msg) {
    if (!is.null(msg$cyls)) {
      cyl_vals <- suppressWarnings(as.numeric(unlist(msg$cyls)))
      env$cyl_filter <- cyl_vals[!is.na(cyl_vals)]
    }
    if (!is.null(msg$am)) {
      am_val <- as.character(msg$am)
      if (am_val %in% c("all", "0", "1")) env$am_filter <- am_val
    }
    if (!is.null(msg$hp_min)) {
      val <- suppressWarnings(as.numeric(msg$hp_min))
      if (is.finite(val)) env$hp_min <- val
    }
    if (!is.null(msg$hp_max)) {
      val <- suppressWarnings(as.numeric(msg$hp_max))
      if (is.finite(val)) env$hp_max <- val
    }
    if (env$hp_min > env$hp_max) {
      tmp <- env$hp_min
      env$hp_min <- env$hp_max
      env$hp_max <- tmp
    }
    if (!is.null(msg$x_var) && as.character(msg$x_var) %in% ALLOWED_X_VARS) {
      env$x_var <- as.character(msg$x_var)
      app$recent$set("x_var", env$x_var)
    }
    if (!is.null(msg$y_var) && as.character(msg$y_var) %in% ALLOWED_Y_VARS) {
      env$y_var <- as.character(msg$y_var)
      app$recent$set("y_var", env$y_var)
    }
    if (!is.null(msg$plot_type) && as.character(msg$plot_type) %in% ALLOWED_PLOT_TYPES) {
      env$plot_type <- as.character(msg$plot_type)
      app$recent$set("plot_type", env$plot_type)
    }
    if (!is.null(msg$smooth_method) && as.character(msg$smooth_method) %in% ALLOWED_SMOOTH) {
      env$smooth_method <- as.character(msg$smooth_method)
    }

    apply_filters(env)
    push_update(app, env)
  })

  # Backwards-compatible aliases
  app$on_message("set_cyl_filter", function(msg) {
    env$cyl_filter <- suppressWarnings(as.numeric(unlist(msg$cyls)))
    apply_filters(env)
    push_update(app, env)
  })

  app$on_message("toggle_plot_type", function(msg) {
    if (!is.null(msg$type) && as.character(msg$type) %in% ALLOWED_PLOT_TYPES) {
      env$plot_type <- as.character(msg$type)
      app$recent$set("plot_type", env$plot_type)
    }
    push_update(app, env)
  })

  app$on_message("reset_filters", function(msg) {
    env$cyl_filter    <- c(4, 6, 8)
    env$am_filter     <- "all"
    env$hp_min        <- min(env$df$hp, na.rm = TRUE)
    env$hp_max        <- max(env$df$hp, na.rm = TRUE)
    env$x_var         <- "wt"
    env$y_var         <- "mpg"
    env$plot_type     <- "scatter"
    env$smooth_method <- "lm"
    app$recent$set("plot_type", env$plot_type)
    app$recent$set("x_var", env$x_var)
    app$recent$set("y_var", env$y_var)

    apply_filters(env)
    push_update(app, env)
    app$send("init_ui_state", list(
      plot_type     = env$plot_type,
      x_var         = env$x_var,
      y_var         = env$y_var,
      smooth_method = env$smooth_method,
      cyl_filter    = I(as.numeric(env$cyl_filter)),
      am_filter     = env$am_filter,
      hp_min        = env$hp_min,
      hp_max        = env$hp_max,
      hp_bounds     = list(
        min = min(env$df$hp, na.rm = TRUE),
        max = max(env$df$hp, na.rm = TRUE)
      )
    ))
    app$toast("Telemetry filters reset to full fleet", type = "info")
  })

  # -- async regression & diagnostics lab -----------------------------------
  app$on_message("run_model", RDesk::async(function(payload) {
    fit_regression_model(
      payload,
      progress_cb = function(pct, msg) RDesk::async_progress(pct, msg)
    )
  }, app = app, loading_message = "Fitting OLS regression & diagnostics..."))

  app$on_message("sync_model_result", function(msg) {
    env$last_model <- list(
      formula          = msg$formula,
      r_squared        = msg$r_squared,
      summary_text     = msg$summary_text,
      markdown_section = msg$markdown_section
    )
  })

  app$on_message("copy_model_summary", function(msg) {
    txt <- if (!is.null(msg$text) && nzchar(msg$text)) {
      as.character(msg$text)
    } else if (!is.null(env$last_model) && !is.null(env$last_model$summary_text)) {
      as.character(env$last_model$summary_text)
    } else {
      NULL
    }

    if (is.null(txt) || !nzchar(txt)) {
      app$toast("Run a regression model first to copy its summary.", type = "warning")
      return(invisible(NULL))
    }

    app$clipboard_write(txt)
    app$toast("Model summary copied to clipboard", type = "success")
  })

  # -- native exports -------------------------------------------------------
  do_export_csv <- function() {
    path <- app$dialog_save(
      title        = "Export Filtered Telemetry (CSV)",
      default_name = "cars_telemetry_filtered.csv",
      filters      = list("CSV files" = "*.csv")
    )
    if (!is.null(path) && nzchar(path)) {
      utils::write.csv(env$filtered, path, row.names = FALSE)
      app$toast(
        sprintf("Exported %d vehicles to %s", nrow(env$filtered), basename(path)),
        type = "success"
      )
    }
  }

  do_export_report <- function(model_override = NULL) {
    path <- app$dialog_save(
      title        = "Export Engineering Report (Markdown)",
      default_name = "cars_engineering_report.md",
      filters      = list("Markdown files" = "*.md")
    )
    if (!is.null(path) && nzchar(path)) {
      model_data <- if (!is.null(model_override) && !is.null(model_override$markdown_section)) {
        model_override
      } else {
        env$last_model
      }
      report_md <- build_markdown_report(env$filtered, env, model_res = model_data)
      writeLines(report_md, con = path, useBytes = TRUE)
      app$toast(
        sprintf("Saved engineering report to %s", basename(path)),
        type = "success"
      )
    }
  }

  app$on_message("export_csv", function(msg) {
    do_export_csv()
  })

  app$on_message("export_report", function(msg) {
    do_export_report(model_override = msg$model)
  })

  # -- native menu bar ------------------------------------------------------
  app$on_ready(function() {
    app$set_menu(list(
      File = list(
        "Reset Workbench"           = function() {
          init_data(env)
          app$recent$remove("plot_type")
          app$recent$remove("x_var")
          app$recent$remove("y_var")
          push_update(app, env)
          app$send("init_ui_state", list(
            plot_type     = env$plot_type,
            x_var         = env$x_var,
            y_var         = env$y_var,
            smooth_method = env$smooth_method,
            cyl_filter    = I(as.numeric(env$cyl_filter)),
            am_filter     = env$am_filter,
            hp_min        = env$hp_min,
            hp_max        = env$hp_max,
            hp_bounds     = list(
              min = min(env$df$hp, na.rm = TRUE),
              max = max(env$df$hp, na.rm = TRUE)
            )
          ))
          app$toast("Workbench state reset", type = "info")
        },
        "---",
        "Export Filtered CSV..."    = function() do_export_csv(),
        "Export Markdown Report..." = function() do_export_report(),
        "---",
        "Exit"                      = app$quit
      ),
      Section = list(
        "Telemetry Explorer"        = function() app$send("__trigger__", list(action = "nav", target = "explorer")),
        "Regression Lab"            = function() app$send("__trigger__", list(action = "nav", target = "models")),
        "Export & Report"           = function() app$send("__trigger__", list(action = "nav", target = "export"))
      ),
      Help = list(
        "About CarsAnalyser"        = function() {
          app$toast("CarsAnalyser · Automotive Performance & Regression Telemetry Workbench (RDesk)", type = "info")
        }
      )
    ))
  })
}
