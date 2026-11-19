# inst/apps/mtcars_dashboard/R/data.R
# Data preparation, filtering, engineering KPIs, and report formatting

build_fleet_df <- function() {
  df <- datasets::mtcars
  df$model <- rownames(datasets::mtcars)
  rownames(df) <- NULL
  df$transmission <- ifelse(df$am == 1, "Manual", "Automatic")
  df$engine_shape <- ifelse(df$vs == 1, "Straight", "V-Shaped")
  df$wt_lbs <- round(df$wt * 1000, 0)
  # wt is in 1,000 lbs -> short tons (2,000 lbs) = wt / 2
  df$hp_per_ton <- round(df$hp / (df$wt * 0.5), 1)

  cols <- c(
    "model", "mpg", "cyl", "disp", "hp", "drat", "wt", "wt_lbs",
    "hp_per_ton", "qsec", "vs", "am", "gear", "carb",
    "transmission", "engine_shape"
  )
  df[, cols, drop = FALSE]
}

init_data <- function(env) {
  env$df            <- build_fleet_df()
  env$filtered      <- env$df
  env$x_var         <- "wt"
  env$y_var         <- "mpg"
  env$cyl_filter    <- c(4, 6, 8)
  env$am_filter     <- "all"
  env$hp_min        <- min(env$df$hp, na.rm = TRUE)
  env$hp_max        <- max(env$df$hp, na.rm = TRUE)
  env$plot_type     <- "scatter"
  env$smooth_method <- "lm"
  env$last_model    <- NULL
  invisible(env)
}

filter_fleet <- function(df, cyl_filter = c(4, 6, 8), am_filter = "all",
                         hp_min = 0, hp_max = Inf) {
  if (length(cyl_filter) == 0) {
    return(df[0, , drop = FALSE])
  }
  cyl_vals <- suppressWarnings(as.numeric(cyl_filter))
  cyl_vals <- cyl_vals[!is.na(cyl_vals)]

  out <- dplyr::filter(
    df,
    cyl %in% cyl_vals,
    hp >= as.numeric(hp_min),
    hp <= as.numeric(hp_max)
  )

  if (identical(as.character(am_filter), "0")) {
    out <- dplyr::filter(out, am == 0)
  } else if (identical(as.character(am_filter), "1")) {
    out <- dplyr::filter(out, am == 1)
  }

  out
}

apply_filters <- function(env) {
  env$filtered <- filter_fleet(
    env$df,
    cyl_filter = env$cyl_filter,
    am_filter  = env$am_filter,
    hp_min     = env$hp_min,
    hp_max     = env$hp_max
  )
  invisible(env$filtered)
}

kpis <- function(df, total_n = nrow(datasets::mtcars)) {
  n <- nrow(df)
  if (n == 0) {
    return(list(
      n               = 0L,
      total           = as.integer(total_n),
      mean_mpg        = NULL,
      mean_hp         = NULL,
      mean_wt         = NULL,
      mean_hp_per_ton = NULL,
      mean_qsec       = NULL,
      best_vehicle    = "None",
      best_mpg        = NULL
    ))
  }

  best_idx <- which.max(df$mpg)
  list(
    n               = as.integer(n),
    total           = as.integer(total_n),
    mean_mpg        = round(mean(df$mpg, na.rm = TRUE), 1),
    mean_hp         = round(mean(df$hp, na.rm = TRUE), 1),
    mean_wt         = round(mean(df$wt, na.rm = TRUE) * 1000, 0),
    mean_hp_per_ton = round(mean(df$hp_per_ton, na.rm = TRUE), 1),
    mean_qsec       = round(mean(df$qsec, na.rm = TRUE), 2),
    best_vehicle    = as.character(df$model[best_idx]),
    best_mpg        = round(df$mpg[best_idx], 1)
  )
}

summary_stats <- function(df) {
  if (nrow(df) == 0) {
    return(data.frame(
      cyl            = numeric(0),
      transmission   = character(0),
      count          = integer(0),
      avg_mpg        = numeric(0),
      avg_hp         = numeric(0),
      avg_hp_per_ton = numeric(0),
      avg_qsec       = numeric(0),
      avg_wt         = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  grouped <- dplyr::group_by(df, cyl, transmission)
  res <- dplyr::summarise(
    grouped,
    count          = dplyr::n(),
    avg_mpg        = round(mean(mpg, na.rm = TRUE), 1),
    avg_hp         = round(mean(hp, na.rm = TRUE), 1),
    avg_hp_per_ton = round(mean(hp_per_ton, na.rm = TRUE), 1),
    avg_qsec       = round(mean(qsec, na.rm = TRUE), 2),
    avg_wt         = round(mean(wt, na.rm = TRUE), 2),
    .groups        = "drop"
  )
  dplyr::arrange(res, cyl, transmission)
}

fleet_table <- function(df) {
  if (nrow(df) == 0) {
    return(data.frame(
      model        = character(0),
      cyl          = numeric(0),
      transmission = character(0),
      mpg          = numeric(0),
      hp           = numeric(0),
      wt_lbs       = numeric(0),
      hp_per_ton   = numeric(0),
      qsec         = numeric(0),
      disp         = numeric(0),
      drat         = numeric(0),
      gear         = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  out <- dplyr::select(
    df,
    model, cyl, transmission, mpg, hp, wt_lbs, hp_per_ton, qsec, disp, drat, gear
  )
  dplyr::arrange(out, dplyr::desc(mpg))
}

sig_stars <- function(p) {
  ifelse(
    is.na(p), "",
    ifelse(p < 0.001, "***",
      ifelse(p < 0.01, "**",
        ifelse(p < 0.05, "*",
          ifelse(p < 0.1, ".", ""))))
  )
}

format_pval <- function(p) {
  ifelse(
    is.na(p), "NA",
    ifelse(p < 0.0001, "< 0.0001", sprintf("%.4f", p))
  )
}

build_model_summary_text <- function(formula_str, scope_label, nobs, df_resid,
                                     metrics, coef_df) {
  header <- c(
    "CarsAnalyser :: OLS Regression & Diagnostics Summary",
    strrep("=", 66),
    sprintf("Formula   : %s", formula_str),
    sprintf("Dataset   : %s (n = %d, df_resid = %d)", scope_label, nobs, df_resid),
    sprintf(
      "Fit Stats : R2 = %.4f | Adj R2 = %.4f | F = %.2f (p = %s)",
      metrics$r_squared, metrics$adj_r_squared, metrics$f_statistic,
      format_pval(metrics$f_p_value)
    ),
    sprintf(
      "Info/Err  : AIC = %.2f | Residual Std Error = %.4f",
      metrics$aic, metrics$rse
    ),
    "",
    sprintf(
      "%-16s %10s %10s %8s %19s %10s %s",
      "Term", "Estimate", "Std.Err", "t-Stat", "95% CI", "p-Value", "Sig"
    ),
    strrep("-", 84)
  )

  rows <- vapply(seq_len(nrow(coef_df)), function(i) {
    ci_str <- sprintf("[%6.3f, %6.3f]", coef_df$conf_low[i], coef_df$conf_high[i])
    sprintf(
      "%-16s %10.4f %10.4f %8.2f %19s %10s %s",
      coef_df$term[i],
      coef_df$estimate[i],
      coef_df$std_error[i],
      coef_df$statistic[i],
      ci_str,
      format_pval(coef_df$p_value[i]),
      coef_df$sig[i]
    )
  }, character(1))

  footer <- c(
    strrep("-", 84),
    "Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1"
  )

  paste(c(header, rows, footer), collapse = "\n")
}

build_model_markdown_section <- function(formula_str, scope_label, nobs, df_resid,
                                         metrics, coef_df) {
  lines <- c(
    "## OLS Regression & Diagnostics",
    "",
    sprintf("- **Model Formula**: `%s`", formula_str),
    sprintf("- **Sample**: %s (`n = %d`, residual df = `%d`)", scope_label, nobs, df_resid),
    "",
    "| Metric | Value |",
    "| :--- | ---: |",
    sprintf("| R-Squared (R²) | %.4f |", metrics$r_squared),
    sprintf("| Adjusted R² | %.4f |", metrics$adj_r_squared),
    sprintf("| F-Statistic | %.2f (p = %s) |", metrics$f_statistic, format_pval(metrics$f_p_value)),
    sprintf("| AIC | %.2f |", metrics$aic),
    sprintf("| Residual Std. Error | %.4f |", metrics$rse),
    "",
    "### Model Coefficients (95% CI)",
    "",
    "| Term | Estimate | Std. Error | t-Stat | 95% CI | p-Value | Sig |",
    "| :--- | ---: | ---: | ---: | :---: | ---: | :---: |"
  )

  coef_rows <- vapply(seq_len(nrow(coef_df)), function(i) {
    sprintf(
      "| `%s` | %.4f | %.4f | %.2f | [%.3f, %.3f] | %s | %s |",
      coef_df$term[i],
      coef_df$estimate[i],
      coef_df$std_error[i],
      coef_df$statistic[i],
      coef_df$conf_low[i],
      coef_df$conf_high[i],
      format_pval(coef_df$p_value[i]),
      if (nzchar(coef_df$sig[i])) coef_df$sig[i] else "-"
    )
  }, character(1))

  paste(c(
    lines,
    coef_rows,
    "",
    "_Significance codes: `***` p < 0.001, `**` p < 0.01, `*` p < 0.05, `.` p < 0.1_"
  ), collapse = "\n")
}

build_markdown_report <- function(df, env, model_res = NULL) {
  k <- kpis(df, total_n = nrow(env$df))
  breakdown <- summary_stats(df)
  tbl <- fleet_table(df)

  am_label <- switch(
    as.character(env$am_filter),
    "0" = "Automatic Only",
    "1" = "Manual Only",
    "All Transmissions"
  )
  cyl_label <- if (length(env$cyl_filter) > 0) {
    paste(sort(as.numeric(env$cyl_filter)), collapse = ", ")
  } else {
    "None"
  }

  lines <- c(
    "# CarsAnalyser — Automotive Performance & Regression Engineering Report",
    "",
    sprintf("_Generated: %s_", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    "",
    "## Active Telemetry Filters",
    "",
    sprintf("- **Cylinders**: %s", cyl_label),
    sprintf("- **Transmission**: %s", am_label),
    sprintf("- **Horsepower Range**: %s – %s HP", env$hp_min, env$hp_max),
    sprintf("- **Matched Vehicles**: %d of %d", k$n, k$total),
    "",
    "## Fleet Performance KPIs",
    "",
    "| Metric | Value |",
    "| :--- | ---: |",
    sprintf("| Filtered Fleet Size | %d / %d vehicles |", k$n, k$total),
    sprintf("| Mean Fuel Economy | %s MPG |", if (is.null(k$mean_mpg)) "N/A" else sprintf("%.1f", k$mean_mpg)),
    sprintf("| Mean Power-to-Weight | %s HP/Ton |", if (is.null(k$mean_hp_per_ton)) "N/A" else sprintf("%.1f", k$mean_hp_per_ton)),
    sprintf("| Mean 1/4 Mile Time | %s sec |", if (is.null(k$mean_qsec)) "N/A" else sprintf("%.2f", k$mean_qsec)),
    sprintf("| Mean Horsepower | %s HP |", if (is.null(k$mean_hp)) "N/A" else sprintf("%.1f", k$mean_hp)),
    sprintf("| Mean Curb Weight | %s lbs |", if (is.null(k$mean_wt)) "N/A" else format(k$mean_wt, big.mark = ",")),
    sprintf(
      "| Best Efficiency Vehicle | %s (%s MPG) |",
      k$best_vehicle,
      if (is.null(k$best_mpg)) "N/A" else sprintf("%.1f", k$best_mpg)
    ),
    ""
  )

  # Cylinder & Transmission breakdown
  lines <- c(lines, "## Cylinder & Transmission Breakdown", "")
  if (nrow(breakdown) > 0) {
    lines <- c(
      lines,
      "| Cyl | Transmission | Count | Avg MPG | Avg HP | Avg HP/Ton | Avg 1/4 Mi (s) | Avg Wt (klbs) |",
      "| :---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: |"
    )
    b_rows <- vapply(seq_len(nrow(breakdown)), function(i) {
      sprintf(
        "| %d | %s | %d | %.1f | %.1f | %.1f | %.2f | %.2f |",
        breakdown$cyl[i], breakdown$transmission[i], breakdown$count[i],
        breakdown$avg_mpg[i], breakdown$avg_hp[i], breakdown$avg_hp_per_ton[i],
        breakdown$avg_qsec[i], breakdown$avg_wt[i]
      )
    }, character(1))
    lines <- c(lines, b_rows, "")
  } else {
    lines <- c(lines, "_No vehicles match the current filter selection._", "")
  }

  # Regression section
  if (!is.null(model_res) && !is.null(model_res$markdown_section) && nzchar(model_res$markdown_section)) {
    lines <- c(lines, model_res$markdown_section, "")
  } else {
    lines <- c(
      lines,
      "## OLS Regression & Diagnostics",
      "",
      "_No regression model has been fitted during this session. Run a model in the Regression Lab to include coefficients and fit diagnostics in this report._",
      ""
    )
  }

  # Full filtered telemetry ledger
  lines <- c(lines, "## Filtered Vehicle Telemetry Ledger", "")
  if (nrow(tbl) > 0) {
    lines <- c(
      lines,
      "| Vehicle | Cyl | Trans | MPG | HP | Weight (lbs) | HP/Ton | 1/4 Mi (s) | Disp | Axle | Gears |",
      "| :--- | :---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
    )
    t_rows <- vapply(seq_len(nrow(tbl)), function(i) {
      sprintf(
        "| %s | %d | %s | %.1f | %.0f | %.0f | %.1f | %.2f | %.1f | %.2f | %d |",
        tbl$model[i], tbl$cyl[i], tbl$transmission[i], tbl$mpg[i], tbl$hp[i],
        tbl$wt_lbs[i], tbl$hp_per_ton[i], tbl$qsec[i], tbl$disp[i], tbl$drat[i],
        tbl$gear[i]
      )
    }, character(1))
    lines <- c(lines, t_rows, "")
  } else {
    lines <- c(lines, "_No vehicle telemetry rows to display._", "")
  }

  paste(lines, collapse = "\n")
}
