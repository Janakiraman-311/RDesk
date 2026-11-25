# Publication-quality ggplot2 charts for Clinical & Biostatistical Studio
# All chart functions return a data:image/png;base64,... URI via rdesk_plot_to_base64()

# ── Scientific Theme & Palette Helpers ──────────────────────────────────────

clinical_palette <- function(dark = FALSE) {
  if (isTRUE(dark)) {
    list(
      bg         = "#111827",
      panel_bg   = "#0F172A",
      grid       = "#1E293B",
      axis       = "#334155",
      ink        = "#F1F5F9",
      muted      = "#94A3B8",
      primary    = "#14B8A6",
      secondary  = "#38BDF8",
      warning    = "#F59E0B",
      danger     = "#F87171",
      neutral    = "#64748B",
      mid_tile   = "#1E293B",
      tile_edge  = "#0F172A",
      groups     = c("#94A3B8", "#38BDF8", "#14B8A6", "#F59E0B", "#A78BFA",
                     "#FB7185", "#34D399", "#FBBF24")
    )
  } else {
    list(
      bg         = "#FFFFFF",
      panel_bg   = "#FAFBFD",
      grid       = "#E5EAF0",
      axis       = "#CBD5E1",
      ink        = "#0F172A",
      muted      = "#475569",
      primary    = "#0F766E",
      secondary  = "#1D4ED8",
      warning    = "#D97706",
      danger     = "#BE123C",
      neutral    = "#64748B",
      mid_tile   = "#F8FAFC",
      tile_edge  = "#FFFFFF",
      groups     = c("#64748B", "#0284C7", "#0F766E", "#D97706", "#4F46E5",
                     "#BE123C", "#059669", "#7C3AED")
    )
  }
}

theme_clinical <- function(dark = FALSE, base_size = 11) {
  pal <- clinical_palette(dark)
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.background    = ggplot2::element_rect(fill = pal$bg, colour = NA),
      panel.background   = ggplot2::element_rect(fill = pal$panel_bg, colour = NA),
      panel.grid.major   = ggplot2::element_line(colour = pal$grid, linewidth = 0.35),
      panel.grid.minor   = ggplot2::element_blank(),
      axis.line          = ggplot2::element_line(colour = pal$axis, linewidth = 0.4),
      axis.ticks         = ggplot2::element_line(colour = pal$axis, linewidth = 0.35),
      axis.text          = ggplot2::element_text(colour = pal$muted, size = base_size - 1.5),
      axis.title         = ggplot2::element_text(colour = pal$ink, size = base_size - 0.5, face = "bold"),
      plot.title         = ggplot2::element_text(colour = pal$ink, size = base_size + 2, face = "bold",
                                                 margin = ggplot2::margin(b = 4)),
      plot.subtitle      = ggplot2::element_text(colour = pal$muted, size = base_size - 1,
                                                 margin = ggplot2::margin(b = 10)),
      plot.caption       = ggplot2::element_text(colour = pal$muted, size = base_size - 2.5,
                                                 hjust = 0, margin = ggplot2::margin(t = 8)),
      strip.background   = ggplot2::element_rect(fill = pal$grid, colour = NA),
      strip.text         = ggplot2::element_text(colour = pal$ink, face = "bold", size = base_size - 1),
      legend.background  = ggplot2::element_rect(fill = pal$bg, colour = NA),
      legend.key         = ggplot2::element_rect(fill = pal$bg, colour = NA),
      legend.text        = ggplot2::element_text(colour = pal$ink, size = base_size - 1.5),
      legend.title       = ggplot2::element_text(colour = pal$ink, size = base_size - 1, face = "bold"),
      plot.margin        = ggplot2::margin(12, 16, 10, 12)
    )
}

order_clinical_levels <- function(x) {
  vals <- unique(as.character(x[!is.na(x)]))
  if (all(c("Placebo", "Low-Dose 10mg", "High-Dose 25mg") %in% vals)) {
    ordered <- c("Placebo", "Low-Dose 10mg", "High-Dose 25mg")
    return(c(ordered, setdiff(vals, ordered)))
  }
  if (all(c("50 mg QD", "150 mg QD", "300 mg QD") %in% vals)) {
    ordered <- c("50 mg QD", "150 mg QD", "300 mg QD")
    return(c(ordered, setdiff(vals, ordered)))
  }
  sort(vals)
}

# ── 1. Overview & Completeness Audit Chart ──────────────────────────────────

chart_overview <- function(df, missing_info = NULL, dark = FALSE) {
  pal <- clinical_palette(dark)
  if (is.null(missing_info)) {
    missing_info <- profile_missing(df)
  }

  if (nrow(missing_info) == 0L) {
    p <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5, size = 4.5,
                        label = "No variables available in dataset.",
                        colour = pal$muted) +
      ggplot2::theme_void() +
      ggplot2::theme(plot.background = ggplot2::element_rect(fill = pal$bg, colour = NA))
    return(rdesk_plot_to_base64(p, width = 9.5, height = 4.6, dpi = 120))
  }

  # Show up to 18 variables, prioritizing variables with missingness at the top
  plot_df <- utils::head(missing_info, 18L)
  # Derive completeness directly from raw counts (BR-002: single rounding at display)
  plot_df$pct_complete <- ifelse(
    plot_df$n_total > 0,
    100 * plot_df$n_observed / plot_df$n_total,
    100
  )
  plot_df$status <- ifelse(
    plot_df$n_missing == 0, "Complete (100%)",
    ifelse(plot_df$pct_missing < 5, "Minor Missing (<5%)", "Elevated Missing (>=5%)")
  )
  plot_df$status <- factor(
    plot_df$status,
    levels = c("Complete (100%)", "Minor Missing (<5%)", "Elevated Missing (>=5%)")
  )
  plot_df$label <- ifelse(
    plot_df$n_missing > 0,
    paste0(fmt_pct(plot_df$pct_complete, 1L), "  (", as.integer(plot_df$n_missing), " NA)"),
    "100.0%"
  )
  plot_df$variable <- factor(plot_df$variable, levels = rev(plot_df$variable))

  status_cols <- c(
    "Complete (100%)"         = pal$primary,
    "Minor Missing (<5%)"     = pal$warning,
    "Elevated Missing (>=5%)" = pal$danger
  )

  overall_comp <- if (length(df) > 0L) mean(!is.na(df)) * 100 else 100
  cc_pct <- if (nrow(df) > 0L) mean(stats::complete.cases(df)) * 100 else 100

  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = variable, y = pct_complete, fill = status)) +
    ggplot2::geom_col(width = 0.68, alpha = 0.9) +
    ggplot2::geom_hline(yintercept = 95, linetype = "dashed", colour = pal$muted, linewidth = 0.45) +
    ggplot2::geom_text(
      ggplot2::aes(label = label),
      hjust = -0.08,
      size = 3.0,
      colour = pal$ink,
      fontface = "plain"
    ) +
    ggplot2::coord_flip(ylim = c(0, 118)) +
    ggplot2::scale_fill_manual(values = status_cols, drop = TRUE) +
    ggplot2::scale_y_continuous(breaks = c(0, 25, 50, 75, 95, 100),
                                labels = function(b) paste0(b, "%")) +
    ggplot2::labs(
      title    = "Variable Completeness & Data Quality Audit",
      subtitle = sprintf("Overall cell completeness: %s  |  Complete cases: %s (n = %d / %d)  |  Dashed line = 95%% clinical benchmark",
                         fmt_pct(overall_comp, 2L), fmt_pct(cc_pct, 1L),
                         sum(stats::complete.cases(df)), nrow(df)),
      x        = NULL,
      y        = "Observed Completeness (%)",
      fill     = "Audit Status"
    ) +
    theme_clinical(dark = dark, base_size = 11) +
    ggplot2::theme(
      panel.grid.major.y = ggplot2::element_blank(),
      legend.position    = "top",
      legend.justification = "left",
      legend.title       = ggplot2::element_blank()
    )

  rdesk_plot_to_base64(p, width = 9.5, height = 4.6, dpi = 120)
}

# ── 2. Interactive Distributions Explorer Chart ─────────────────────────────

chart_distributions <- function(df,
                                variable = NULL,
                                group_by = NULL,
                                plot_mode = "density",
                                dark = FALSE) {
  pal <- clinical_palette(dark)
  num_cols <- get_numeric_cols(df)

  if (length(num_cols) == 0L) {
    p <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5, size = 4.5,
                        label = "No numeric variables available for distribution analysis.",
                        colour = pal$danger) +
      ggplot2::theme_void() +
      ggplot2::theme(plot.background = ggplot2::element_rect(fill = pal$bg, colour = NA))
    return(rdesk_plot_to_base64(p, width = 9.5, height = 5.0, dpi = 120))
  }

  if (is.null(variable) || !nzchar(variable) || !(variable %in% num_cols)) {
    variable <- pick_default_var(df)
  }

  use_group <- !is.null(group_by) && nzchar(group_by) &&
    group_by != "none" && (group_by %in% names(df))

  raw_x <- df[[variable]]
  if (use_group) {
    g_raw <- as.character(df[[group_by]])
    ok <- is.finite(raw_x) & !is.na(g_raw) & nzchar(g_raw)
    plot_df <- data.frame(
      value = raw_x[ok],
      group = factor(g_raw[ok], levels = order_clinical_levels(g_raw[ok])),
      stringsAsFactors = FALSE
    )
    if (length(levels(plot_df$group)) < 2L || length(levels(plot_df$group)) > 12L) {
      use_group <- FALSE
    }
  }

  if (!use_group) {
    ok <- is.finite(raw_x)
    plot_df <- data.frame(value = raw_x[ok], stringsAsFactors = FALSE)
  }

  if (nrow(plot_df) < 2L) {
    p <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5, size = 4.5,
                        label = paste0("Insufficient finite observations for '", variable, "'."),
                        colour = pal$muted) +
      ggplot2::theme_void() +
      ggplot2::theme(plot.background = ggplot2::element_rect(fill = pal$bg, colour = NA))
    return(rdesk_plot_to_base64(p, width = 9.5, height = 5.0, dpi = 120))
  }

  mean_v <- mean(plot_df$value)
  sd_v   <- stats::sd(plot_df$value)
  med_v  <- stats::median(plot_df$value)
  iqr_v  <- stats::IQR(plot_df$value)
  sw_p   <- compute_shapiro_p(plot_df$value)

  # Dynamic Freedman-Diaconis / Sturges bin count
  n_bins <- min(36L, max(12L, as.integer(round(grDevices::nclass.Sturges(plot_df$value) * 1.8))))

  if (!use_group) {
    if (identical(plot_mode, "violin")) {
      plot_df$cohort <- "All Subjects"
      p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = cohort, y = value)) +
        ggplot2::geom_violin(fill = pal$primary, colour = pal$primary, alpha = 0.25, linewidth = 0.65, trim = FALSE) +
        ggplot2::geom_boxplot(width = 0.16, fill = pal$bg, colour = pal$primary,
                              outlier.colour = pal$danger, outlier.size = 2.0, linewidth = 0.6) +
        ggplot2::geom_jitter(width = 0.08, alpha = 0.35, size = 1.3, colour = pal$secondary) +
        ggplot2::stat_summary(fun = mean, geom = "point", shape = 18, size = 3.8, colour = pal$warning) +
        ggplot2::coord_flip() +
        ggplot2::labs(
          title    = sprintf("Distribution of %s — Violin & Boxplot", variable),
          subtitle = sprintf("n = %d  |  Mean = %s (SD = %s)  |  Median = %s (IQR = %s)  |  Shapiro-Wilk p %s",
                             nrow(plot_df), fmt_fixed(mean_v, 2L), fmt_fixed(sd_v, 2L),
                             fmt_fixed(med_v, 2L), fmt_fixed(iqr_v, 2L),
                             ifelse(is.na(sw_p), "N/A", ifelse(sw_p < 0.0001, "< 0.0001", paste("=", fmt_p_value(sw_p))))),
          x        = NULL,
          y        = variable,
          caption  = "Diamond marker indicates arithmetic mean; red points denote Tukey 1.5x IQR outliers."
        ) +
        theme_clinical(dark = dark, base_size = 11) +
        ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())
    } else {
      p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = value)) +
        ggplot2::geom_histogram(
          ggplot2::aes(y = ggplot2::after_stat(density)),
          bins = n_bins,
          fill = pal$primary,
          colour = pal$bg,
          alpha = 0.45,
          linewidth = 0.35
        ) +
        ggplot2::geom_density(colour = pal$primary, linewidth = 1.0) +
        ggplot2::geom_vline(xintercept = mean_v, colour = pal$danger, linetype = "dashed", linewidth = 0.75) +
        ggplot2::geom_vline(xintercept = med_v, colour = pal$secondary, linetype = "solid", linewidth = 0.75) +
        ggplot2::geom_rug(alpha = 0.25, colour = pal$muted, length = grid::unit(0.025, "npc")) +
        ggplot2::labs(
          title    = sprintf("Distribution of %s — Histogram & Kernel Density", variable),
          subtitle = sprintf("n = %d  |  Mean (dashed red) = %s  |  Median (solid blue) = %s  |  SD = %s  |  Shapiro-Wilk p %s",
                             nrow(plot_df), fmt_fixed(mean_v, 2L), fmt_fixed(med_v, 2L), fmt_fixed(sd_v, 2L),
                             ifelse(is.na(sw_p), "N/A", ifelse(sw_p < 0.0001, "< 0.0001", paste("=", fmt_p_value(sw_p))))),
          x        = variable,
          y        = "Probability Density"
        ) +
        theme_clinical(dark = dark, base_size = 11)
    }
  } else {
    # Stratified by group_by
    n_grps <- length(levels(plot_df$group))
    grp_cols <- rep(pal$groups, length.out = n_grps)
    names(grp_cols) <- levels(plot_df$group)

    # Group means for reference markers
    grp_means <- stats::aggregate(value ~ group, data = plot_df, FUN = mean)
    p_test <- tryCatch({
      if (n_grps == 2L) stats::t.test(value ~ group, data = plot_df)$p.value
      else stats::oneway.test(value ~ group, data = plot_df)$p.value
    }, error = function(e) NA_real_)
    test_name <- if (n_grps == 2L) "Welch t-test" else "Welch ANOVA"

    if (identical(plot_mode, "violin")) {
      p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = group, y = value, fill = group, colour = group)) +
        ggplot2::geom_violin(alpha = 0.24, linewidth = 0.65, trim = FALSE, show.legend = FALSE) +
        ggplot2::geom_boxplot(width = 0.18, fill = pal$bg, alpha = 0.9,
                              outlier.colour = pal$danger, outlier.size = 1.9,
                              linewidth = 0.6, show.legend = FALSE) +
        ggplot2::geom_jitter(width = 0.09, alpha = 0.35, size = 1.3, show.legend = FALSE) +
        ggplot2::stat_summary(fun = mean, geom = "point", shape = 18, size = 3.6,
                              colour = pal$warning, show.legend = FALSE) +
        ggplot2::scale_fill_manual(values = grp_cols) +
        ggplot2::scale_colour_manual(values = grp_cols) +
        ggplot2::labs(
          title    = sprintf("%s Stratified by %s — Violin & Boxplot", variable, group_by),
          subtitle = sprintf("n = %d across %d cohorts  |  %s p %s  |  Amber diamonds = group means",
                             nrow(plot_df), n_grps, test_name,
                             ifelse(is.na(p_test), "N/A", ifelse(p_test < 0.0001, "< 0.0001", paste("=", format_p_value(p_test))))),
          x        = group_by,
          y        = variable
        ) +
        theme_clinical(dark = dark, base_size = 11) +
        ggplot2::theme(
          axis.text.x = ggplot2::element_text(angle = if (n_grps > 4L) 20 else 0,
                                              hjust = if (n_grps > 4L) 1 else 0.5)
        )
    } else {
      # Histogram + Kernel Density faceted cleanly by group so distributions never muddy each other
      p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = value, fill = group, colour = group)) +
        ggplot2::geom_histogram(
          ggplot2::aes(y = ggplot2::after_stat(density)),
          bins = min(24L, max(10L, as.integer(n_bins * 0.8))),
          alpha = 0.32,
          colour = pal$bg,
          linewidth = 0.25,
          show.legend = FALSE
        ) +
        ggplot2::geom_density(linewidth = 0.95, fill = NA, show.legend = FALSE) +
        ggplot2::geom_vline(
          data = grp_means,
          ggplot2::aes(xintercept = value, colour = group),
          linetype = "dashed",
          linewidth = 0.75,
          show.legend = FALSE
        ) +
        ggplot2::facet_wrap(~ group, ncol = min(3L, n_grps), scales = "free_y") +
        ggplot2::scale_fill_manual(values = grp_cols) +
        ggplot2::scale_colour_manual(values = grp_cols) +
        ggplot2::labs(
          title    = sprintf("%s Stratified by %s — Histogram & Kernel Density", variable, group_by),
          subtitle = sprintf("n = %d across %d cohorts  |  %s p %s  |  Dashed vertical lines = cohort means",
                             nrow(plot_df), n_grps, test_name,
                             ifelse(is.na(p_test), "N/A", ifelse(p_test < 0.0001, "< 0.0001", paste("=", format_p_value(p_test))))),
          x        = variable,
          y        = "Probability Density"
        ) +
        theme_clinical(dark = dark, base_size = 11)
    }
  }

  rdesk_plot_to_base64(p, width = 9.5, height = 5.0, dpi = 120)
}

# ── 3. Correlation Matrix Heatmap ───────────────────────────────────────────

chart_correlations <- function(df, method = "pearson", dark = FALSE) {
  pal <- clinical_palette(dark)
  num_cols <- get_numeric_cols(df)

  if (length(num_cols) < 2L) {
    p <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5, size = 4.5,
                        label = "At least 2 numeric variables are required for correlation analysis.",
                        colour = pal$danger) +
      ggplot2::theme_void() +
      ggplot2::theme(plot.background = ggplot2::element_rect(fill = pal$bg, colour = NA))
    return(rdesk_plot_to_base64(p, width = 8.8, height = 6.4, dpi = 120))
  }

  # Cap at 14 numeric variables for legibility on high-dimensional user files
  if (length(num_cols) > 14L) {
    num_cols <- utils::head(num_cols, 14L)
  }

  method <- match.arg(method, c("pearson", "spearman", "kendall"))
  num_df <- df[, num_cols, drop = FALSE]
  corr_mat <- suppressWarnings(stats::cor(num_df, use = "pairwise.complete.obs", method = method))

  corr_df <- as.data.frame(as.table(corr_mat), stringsAsFactors = FALSE)
  colnames(corr_df) <- c("Var1", "Var2", "value")
  corr_df$Var1 <- factor(corr_df$Var1, levels = num_cols)
  corr_df$Var2 <- factor(corr_df$Var2, levels = rev(num_cols))
  corr_df$label <- ifelse(is.na(corr_df$value), "--", fmt_fixed(corr_df$value, 2L))
  corr_df$txt_col <- ifelse(!is.na(corr_df$value) & abs(corr_df$value) >= 0.45,
                            "#FFFFFF", pal$ink)

  method_title <- switch(
    method,
    pearson  = "Pearson Product-Moment Correlation Matrix (r)",
    spearman = "Spearman Rank Correlation Matrix (rho)",
    kendall  = "Kendall Rank Correlation Matrix (tau)"
  )
  legend_lbl <- switch(method, pearson = "r", spearman = "rho", kendall = "tau")

  txt_size <- if (length(num_cols) <= 10L) 3.1 else 2.5

  p <- ggplot2::ggplot(corr_df, ggplot2::aes(x = Var1, y = Var2, fill = value)) +
    ggplot2::geom_tile(colour = pal$tile_edge, linewidth = 0.7) +
    ggplot2::geom_text(
      ggplot2::aes(label = label, colour = txt_col),
      size = txt_size,
      fontface = "bold",
      show.legend = FALSE
    ) +
    ggplot2::scale_colour_identity() +
    ggplot2::scale_fill_gradient2(
      low      = if (dark) "#DC2626" else "#B91C1C",
      mid      = pal$mid_tile,
      high     = if (dark) "#0D9488" else "#0F766E",
      midpoint = 0,
      limits   = c(-1, 1),
      na.value = pal$grid,
      breaks   = c(-1, -0.5, 0, 0.5, 1)
    ) +
    ggplot2::coord_fixed() +
    ggplot2::labs(
      title    = method_title,
      subtitle = sprintf("Pairwise complete observations across %d numeric variables", length(num_cols)),
      x        = NULL,
      y        = NULL,
      fill     = legend_lbl
    ) +
    theme_clinical(dark = dark, base_size = 11) +
    ggplot2::theme(
      panel.grid       = ggplot2::element_blank(),
      axis.line        = ggplot2::element_blank(),
      axis.ticks       = ggplot2::element_blank(),
      axis.text.x      = ggplot2::element_text(angle = 38, hjust = 1, colour = pal$ink),
      axis.text.y      = ggplot2::element_text(colour = pal$ink),
      legend.key.height = grid::unit(1.4, "cm")
    )

  rdesk_plot_to_base64(p, width = 8.8, height = 6.4, dpi = 120)
}

# ── 4. Tukey IQR Outlier Diagnostic Plot ────────────────────────────────────

chart_outliers <- function(df, outlier_table = NULL, threshold = 1.5, dark = FALSE) {
  pal <- clinical_palette(dark)
  if (is.null(outlier_table)) {
    outlier_table <- detect_outliers(df, threshold = threshold)
  }

  num_cols <- get_numeric_cols(df)
  if (length(num_cols) == 0L || nrow(outlier_table) == 0L) {
    p <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5, size = 4.5,
                        label = "No numeric variables available for outlier screening.",
                        colour = pal$muted) +
      ggplot2::theme_void() +
      ggplot2::theme(plot.background = ggplot2::element_rect(fill = pal$bg, colour = NA))
    return(rdesk_plot_to_base64(p, width = 9.5, height = 5.4, dpi = 120))
  }

  # Prioritize variables with outliers, showing up to 8 variables in a clean native-scale faceted grid
  ordered_vars <- outlier_table$variable
  flagged_vars <- outlier_table$variable[outlier_table$n_outliers > 0]
  show_vars <- if (length(flagged_vars) >= 4L) {
    utils::head(flagged_vars, 8L)
  } else {
    utils::head(ordered_vars, 8L)
  }

  long_list <- lapply(show_vars, function(col) {
    x <- df[[col]]
    x <- x[is.finite(x)]
    if (length(x) < 4L) return(NULL)
    q1  <- as.numeric(stats::quantile(x, 0.25, names = FALSE))
    q3  <- as.numeric(stats::quantile(x, 0.75, names = FALSE))
    iqr <- q3 - q1
    lo  <- q1 - threshold * iqr
    hi  <- q3 + threshold * iqr
    is_out <- (x < lo) | (x > hi)
    n_out  <- sum(is_out)
    facet_lbl <- sprintf("%s (%d flagged)", col, n_out)

    data.frame(
      variable = facet_lbl,
      value    = x,
      status   = ifelse(is_out, "Outlier", "Within Fence"),
      lo       = lo,
      hi       = hi,
      stringsAsFactors = FALSE
    )
  })
  long_list <- Filter(Negate(is.null), long_list)

  if (length(long_list) == 0L) {
    p <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5, size = 4.5,
                        label = "Insufficient observations for Tukey IQR diagnostics.",
                        colour = pal$muted) +
      ggplot2::theme_void() +
      ggplot2::theme(plot.background = ggplot2::element_rect(fill = pal$bg, colour = NA))
    return(rdesk_plot_to_base64(p, width = 9.5, height = 5.4, dpi = 120))
  }

  plot_df <- do.call(rbind, long_list)
  plot_df$variable <- factor(plot_df$variable, levels = unique(plot_df$variable))
  plot_df$status <- factor(plot_df$status, levels = c("Within Fence", "Outlier"))

  fence_df <- unique(plot_df[, c("variable", "lo", "hi")])
  total_flagged <- sum(outlier_table$n_outliers, na.rm = TRUE)

  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = "", y = value)) +
    ggplot2::geom_boxplot(
      width = 0.42,
      fill = pal$primary,
      colour = pal$ink,
      alpha = 0.20,
      outlier.shape = NA,
      linewidth = 0.55
    ) +
    ggplot2::geom_jitter(
      ggplot2::aes(colour = status, size = status, alpha = status),
      width = 0.16
    ) +
    ggplot2::geom_hline(
      data = fence_df,
      ggplot2::aes(yintercept = lo),
      linetype = "dashed", colour = pal$danger, linewidth = 0.45, alpha = 0.75
    ) +
    ggplot2::geom_hline(
      data = fence_df,
      ggplot2::aes(yintercept = hi),
      linetype = "dashed", colour = pal$danger, linewidth = 0.45, alpha = 0.75
    ) +
    ggplot2::facet_wrap(~ variable, scales = "free_y", ncol = min(4L, length(unique(plot_df$variable)))) +
    ggplot2::scale_colour_manual(values = c("Within Fence" = pal$secondary, "Outlier" = pal$danger)) +
    ggplot2::scale_size_manual(values = c("Within Fence" = 1.25, "Outlier" = 2.4)) +
    ggplot2::scale_alpha_manual(values = c("Within Fence" = 0.35, "Outlier" = 0.95)) +
    ggplot2::labs(
      title    = sprintf("Tukey IQR Outlier Audit (%sx IQR Fence)", fmt_fixed(threshold, 1L)),
      subtitle = sprintf("%d total flagged observations across %d of %d numeric variables  |  Dashed lines = lower/upper Tukey fences",
                         total_flagged, sum(outlier_table$n_outliers > 0), nrow(outlier_table)),
      x        = NULL,
      y        = "Observed Value (Native Units)",
      colour   = NULL,
      size     = NULL,
      alpha    = NULL
    ) +
    theme_clinical(dark = dark, base_size = 10.5) +
    ggplot2::theme(
      axis.text.x        = ggplot2::element_blank(),
      axis.ticks.x       = ggplot2::element_blank(),
      panel.grid.major.x = ggplot2::element_blank(),
      legend.position    = "top",
      legend.justification = "left"
    )

  rdesk_plot_to_base64(p, width = 9.5, height = 5.4, dpi = 120)
}

# ── Backwards-Compatible Aliases ────────────────────────────────────────────

make_overview_chart      <- chart_overview
make_distribution_charts <- chart_distributions
make_correlation_chart   <- chart_correlations
make_outlier_chart       <- chart_outliers
