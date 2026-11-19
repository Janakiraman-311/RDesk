# inst/apps/mtcars_dashboard/R/plots.R
# Dark-surface telemetry visualizations and regression diagnostic plots

TELEMETRY_SURFACE <- "#1e293b"
TELEMETRY_WELL    <- "#0f172a"
TELEMETRY_GRID    <- "#334155"
TELEMETRY_TEXT    <- "#f8fafc"
TELEMETRY_SUB     <- "#94a3b8"
TELEMETRY_MUTED   <- "#64748b"
TELEMETRY_ACCENT  <- "#38bdf8"
TELEMETRY_ALERT   <- "#fb7185"

CYL_PALETTE <- c(
  "4" = "#34d399",
  "6" = "#38bdf8",
  "8" = "#f59e0b"
)

VAR_LABELS <- c(
  mpg        = "Fuel Economy (MPG)",
  wt         = "Curb Weight (1,000 lbs)",
  hp         = "Gross Horsepower (HP)",
  disp       = "Displacement (cu. in.)",
  drat       = "Rear Axle Ratio",
  qsec       = "1/4 Mile Time (sec)",
  hp_per_ton = "Power-to-Weight (HP / Ton)"
)

var_label <- function(var_name) {
  lbl <- unname(VAR_LABELS[var_name])
  if (is.na(lbl) || !nzchar(lbl)) toupper(var_name) else lbl
}

plot_to_b64 <- function(p, w = 860, h = 420, dpi = 120) {
  tmp <- tempfile(fileext = ".png")
  on.exit(unlink(tmp), add = TRUE)
  ggplot2::ggsave(
    filename = tmp,
    plot     = p,
    width    = w / 96,
    height   = h / 96,
    dpi      = dpi,
    device   = "png",
    bg       = TELEMETRY_SURFACE
  )
  raw <- readBin(tmp, "raw", file.info(tmp)$size)
  paste0("data:image/png;base64,", base64enc::base64encode(raw))
}

theme_telemetry <- function(base_size = 11) {
  ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.background   = ggplot2::element_rect(fill = TELEMETRY_SURFACE, color = NA),
      panel.background  = ggplot2::element_rect(fill = TELEMETRY_SURFACE, color = NA),
      panel.grid.major  = ggplot2::element_line(color = TELEMETRY_GRID, linewidth = 0.35),
      panel.grid.minor  = ggplot2::element_blank(),
      panel.border      = ggplot2::element_blank(),
      axis.line         = ggplot2::element_line(color = "#475569", linewidth = 0.4),
      axis.ticks        = ggplot2::element_line(color = "#475569", linewidth = 0.35),
      axis.text         = ggplot2::element_text(color = TELEMETRY_SUB, size = base_size - 1.5),
      axis.title.x      = ggplot2::element_text(
        color = "#cbd5e1", size = base_size - 0.5, face = "bold",
        margin = ggplot2::margin(t = 8)
      ),
      axis.title.y      = ggplot2::element_text(
        color = "#cbd5e1", size = base_size - 0.5, face = "bold",
        margin = ggplot2::margin(r = 8)
      ),
      plot.title        = ggplot2::element_text(
        color = TELEMETRY_TEXT, size = base_size + 1.5, face = "bold",
        hjust = 0, margin = ggplot2::margin(b = 3)
      ),
      plot.subtitle     = ggplot2::element_text(
        color = TELEMETRY_SUB, size = base_size - 1.2,
        hjust = 0, margin = ggplot2::margin(b = 10)
      ),
      plot.caption      = ggplot2::element_text(
        color = TELEMETRY_MUTED, size = base_size - 2.2,
        hjust = 1, margin = ggplot2::margin(t = 8)
      ),
      plot.margin       = ggplot2::margin(14, 16, 12, 14),
      legend.background = ggplot2::element_rect(fill = TELEMETRY_SURFACE, color = NA),
      legend.key        = ggplot2::element_rect(fill = TELEMETRY_SURFACE, color = NA),
      legend.title      = ggplot2::element_text(color = "#cbd5e1", size = base_size - 1.5, face = "bold"),
      legend.text       = ggplot2::element_text(color = TELEMETRY_SUB, size = base_size - 1.8),
      legend.position   = "top",
      legend.justification = "left",
      legend.box.spacing = ggplot2::unit(4, "pt"),
      strip.background  = ggplot2::element_rect(fill = TELEMETRY_WELL, color = TELEMETRY_GRID, linewidth = 0.4),
      strip.text        = ggplot2::element_text(color = TELEMETRY_TEXT, face = "bold", size = base_size - 1.5)
    )
}

make_empty_plot <- function(message = "No vehicles match the active filter criteria") {
  ggplot2::ggplot() +
    ggplot2::annotate(
      "text",
      x = 0.5, y = 0.5,
      label = message,
      color = TELEMETRY_SUB,
      size = 4.2,
      fontface = "bold"
    ) +
    ggplot2::xlim(0, 1) +
    ggplot2::ylim(0, 1) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.background  = ggplot2::element_rect(fill = TELEMETRY_SURFACE, color = NA),
      panel.background = ggplot2::element_rect(fill = TELEMETRY_SURFACE, color = NA)
    )
}

compute_pareto_frontier <- function(df) {
  if (nrow(df) == 0) return(df[0, , drop = FALSE])
  ord <- df[order(-df$hp_per_ton, -df$mpg), , drop = FALSE]
  running_max <- -Inf
  keep <- logical(nrow(ord))
  for (i in seq_len(nrow(ord))) {
    if (ord$mpg[i] >= running_max) {
      keep[i] <- TRUE
      running_max <- ord$mpg[i]
    }
  }
  frontier <- ord[keep, , drop = FALSE]
  frontier[order(frontier$hp_per_ton), , drop = FALSE]
}

make_plot <- function(df, x = "wt", y = "mpg", type = "scatter", smooth_method = "lm") {
  if (is.null(df) || nrow(df) == 0) {
    return(make_empty_plot())
  }

  # Ensure derived fields exist even if caller passes plain mtcars + model
  if (!"transmission" %in% names(df)) {
    df$transmission <- ifelse(df$am == 1, "Manual", "Automatic")
  }
  if (!"hp_per_ton" %in% names(df)) {
    df$hp_per_ton <- round(df$hp / (df$wt * 0.5), 1)
  }
  df$cyl_factor <- factor(df$cyl, levels = c(4, 6, 8))

  n_veh <- nrow(df)

  if (identical(type, "boxplot")) {
    p <- ggplot2::ggplot(
      df,
      ggplot2::aes(x = cyl_factor, y = .data[[y]], color = cyl_factor, fill = cyl_factor)
    ) +
      ggplot2::geom_boxplot(
        width = 0.48,
        alpha = 0.22,
        linewidth = 0.75,
        outlier.shape = NA
      ) +
      ggplot2::geom_jitter(
        ggplot2::aes(shape = transmission),
        width = 0.14,
        height = 0,
        size = 2.8,
        alpha = 0.92
      ) +
      ggplot2::stat_summary(
        fun = mean,
        geom = "point",
        shape = 23,
        size = 3.2,
        fill = TELEMETRY_TEXT,
        color = TELEMETRY_WELL,
        stroke = 0.9,
        show.legend = FALSE
      ) +
      ggplot2::scale_color_manual(name = "Cylinders", values = CYL_PALETTE, drop = TRUE) +
      ggplot2::scale_fill_manual(name = "Cylinders", values = CYL_PALETTE, drop = TRUE) +
      ggplot2::scale_shape_manual(
        name = "Trans",
        values = c("Automatic" = 16, "Manual" = 17),
        drop = TRUE
      ) +
      ggplot2::labs(
        title    = paste0(var_label(y), " Distribution by Cylinder Class"),
        subtitle = "IQR box with jittered individual telemetry points · White diamond marks group mean",
        x        = "Engine Configuration (Cylinders)",
        y        = var_label(y),
        caption  = sprintf("n = %d vehicles · Motor Trend 1974 Road Tests", n_veh)
      ) +
      theme_telemetry()

    return(p)
  }

  if (identical(type, "density")) {
    df$cyl_label <- factor(
      paste0(df$cyl, " Cyl"),
      levels = c("4 Cyl", "6 Cyl", "8 Cyl")
    )
    grp_counts <- table(df$cyl_label)
    valid_grps <- names(grp_counts[grp_counts >= 2])

    medians <- dplyr::summarise(
      dplyr::group_by(df, cyl_label, cyl_factor),
      med_val = stats::median(.data[[y]], na.rm = TRUE),
      .groups = "drop"
    )

    density_df <- df[df$cyl_label %in% valid_grps, , drop = FALSE]

    p <- ggplot2::ggplot(df, ggplot2::aes(x = .data[[y]], color = cyl_factor, fill = cyl_factor))

    if (nrow(density_df) >= 2) {
      p <- p +
        ggplot2::geom_density(
          data = density_df,
          alpha = 0.28,
          linewidth = 0.85,
          adjust = 1.05
        )
    }

    p <- p +
      ggplot2::geom_rug(sides = "b", alpha = 0.8, length = ggplot2::unit(0.08, "npc"), linewidth = 0.6) +
      ggplot2::geom_vline(
        data = medians,
        ggplot2::aes(xintercept = med_val, color = cyl_factor),
        linetype = "dashed",
        linewidth = 0.65,
        show.legend = FALSE
      ) +
      ggplot2::facet_grid(cyl_label ~ ., scales = "free_y", switch = "y") +
      ggplot2::scale_color_manual(name = "Cylinders", values = CYL_PALETTE, drop = TRUE) +
      ggplot2::scale_fill_manual(name = "Cylinders", values = CYL_PALETTE, drop = TRUE) +
      ggplot2::labs(
        title    = paste0(var_label(y), " Kernel Density Ridges"),
        subtitle = "Stratified density profile by cylinder bank · Dashed marker denotes group median",
        x        = var_label(y),
        y        = NULL,
        caption  = sprintf("n = %d vehicles · Rug marks show exact observations", n_veh)
      ) +
      theme_telemetry() +
      ggplot2::theme(
        axis.text.y  = ggplot2::element_blank(),
        axis.ticks.y = ggplot2::element_blank(),
        panel.grid.major.y = ggplot2::element_blank(),
        strip.text.y.left = ggplot2::element_text(angle = 0, color = TELEMETRY_TEXT, face = "bold"),
        panel.spacing = ggplot2::unit(6, "pt")
      )

    return(p)
  }

  if (identical(type, "efficiency")) {
    frontier <- compute_pareto_frontier(df)
    p <- ggplot2::ggplot(
      df,
      ggplot2::aes(x = hp_per_ton, y = mpg, color = cyl_factor)
    )

    if (nrow(frontier) >= 2) {
      p <- p +
        ggplot2::geom_line(
          data = frontier,
          ggplot2::aes(x = hp_per_ton, y = mpg),
          inherit.aes = FALSE,
          color = "#cbd5e1",
          linetype = "dashed",
          linewidth = 0.65,
          alpha = 0.65
        )
    }

    p <- p +
      ggplot2::geom_point(
        ggplot2::aes(shape = transmission),
        size = 3.1,
        alpha = 0.85
      )

    if (nrow(frontier) > 0) {
      p <- p +
        ggplot2::geom_point(
          data = frontier,
          ggplot2::aes(x = hp_per_ton, y = mpg, color = cyl_factor),
          shape = 21,
          fill = NA,
          size = 5.4,
          stroke = 1.0,
          show.legend = FALSE
        ) +
        ggplot2::geom_text(
          data = frontier,
          ggplot2::aes(x = hp_per_ton, y = mpg, label = model),
          inherit.aes = FALSE,
          color = TELEMETRY_TEXT,
          size = 2.9,
          fontface = "bold",
          vjust = -1.15,
          hjust = 0.5,
          check_overlap = TRUE
        )
    }

    p <- p +
      ggplot2::scale_color_manual(name = "Cylinders", values = CYL_PALETTE, drop = TRUE) +
      ggplot2::scale_shape_manual(
        name = "Trans",
        values = c("Automatic" = 16, "Manual" = 17),
        drop = TRUE
      ) +
      ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.08, 0.16))) +
      ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0.06, 0.12))) +
      ggplot2::labs(
        title    = "Power-to-Weight Efficiency Frontier",
        subtitle = sprintf(
          "Pareto-optimal vehicles highlighted (%d on frontier) balancing specific output vs. fuel economy",
          nrow(frontier)
        ),
        x        = var_label("hp_per_ton"),
        y        = var_label("mpg"),
        caption  = sprintf("n = %d vehicles · Short ton = 2,000 lbs", n_veh)
      ) +
      theme_telemetry()

    return(p)
  }

  # Default: scatter with OLS or LOESS smooth + confidence band
  fit_method <- if (identical(smooth_method, "loess") && n_veh >= 6) "loess" else "lm"
  fit_label  <- if (fit_method == "loess") "LOESS Smooth" else "OLS Linear Fit"
  can_smooth <- n_veh >= 3 && length(unique(df[[x]])) >= 2

  # Highlight notable extreme points (max Y, min Y, max X) without overcrowding
  callout_idx <- unique(c(
    which.max(df[[y]]),
    which.min(df[[y]]),
    which.max(df[[x]])
  ))
  callout_df <- df[callout_idx, , drop = FALSE]

  p <- ggplot2::ggplot(
    df,
    ggplot2::aes(x = .data[[x]], y = .data[[y]], color = cyl_factor)
  )

  if (can_smooth) {
    p <- p +
      ggplot2::geom_smooth(
        ggplot2::aes(x = .data[[x]], y = .data[[y]]),
        inherit.aes = FALSE,
        method    = fit_method,
        formula   = y ~ x,
        se        = TRUE,
        color     = TELEMETRY_ACCENT,
        fill      = TELEMETRY_ACCENT,
        alpha     = 0.14,
        linewidth = 0.85
      )
  }

  p <- p +
    ggplot2::geom_point(
      ggplot2::aes(shape = transmission),
      size = 3.2,
      alpha = 0.9
    ) +
    ggplot2::geom_text(
      data = callout_df,
      ggplot2::aes(x = .data[[x]], y = .data[[y]], label = model),
      inherit.aes = FALSE,
      color = "#cbd5e1",
      size = 2.8,
      vjust = -1.1,
      hjust = 0.5,
      check_overlap = TRUE
    ) +
    ggplot2::scale_color_manual(name = "Cylinders", values = CYL_PALETTE, drop = TRUE) +
    ggplot2::scale_shape_manual(
      name = "Trans",
      values = c("Automatic" = 16, "Manual" = 17),
      drop = TRUE
    ) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.08, 0.14))) +
    ggplot2::labs(
      title    = paste0(var_label(y), " vs. ", var_label(x)),
      subtitle = if (can_smooth) {
        paste0(fit_label, " with 95% confidence band · Grouped by cylinders & transmission")
      } else {
        "Telemetry scatter · Grouped by cylinders & transmission"
      },
      x        = var_label(x),
      y        = var_label(y),
      caption  = sprintf("n = %d vehicles · Motor Trend 1974", n_veh)
    ) +
    theme_telemetry()

  p
}

make_actual_vs_pred_plot <- function(aug_df, response_var, formula_str = "") {
  if (is.null(aug_df) || nrow(aug_df) == 0) {
    return(make_empty_plot("No diagnostic observations available"))
  }

  aug_df$cyl_factor <- factor(aug_df$cyl, levels = c(4, 6, 8))
  aug_df$.actual <- aug_df[[response_var]]
  aug_df$abs_resid <- abs(aug_df$.resid)

  top_k <- min(3L, nrow(aug_df))
  callout_df <- aug_df[order(-aug_df$abs_resid), , drop = FALSE][seq_len(top_k), , drop = FALSE]

  rng <- range(c(aug_df$.fitted, aug_df$.actual), na.rm = TRUE)
  pad <- diff(rng) * 0.08
  if (!is.finite(pad) || pad == 0) pad <- 1
  lims <- c(rng[1] - pad, rng[2] + pad)

  ggplot2::ggplot(aug_df, ggplot2::aes(x = .fitted, y = .actual)) +
    ggplot2::geom_abline(
      slope = 1, intercept = 0,
      linetype = "dashed",
      color = TELEMETRY_SUB,
      linewidth = 0.65
    ) +
    ggplot2::geom_segment(
      ggplot2::aes(x = .fitted, xend = .fitted, y = .fitted, yend = .actual),
      color = "#64748b",
      alpha = 0.55,
      linewidth = 0.45
    ) +
    ggplot2::geom_point(
      ggplot2::aes(color = cyl_factor),
      size = 2.9,
      alpha = 0.92
    ) +
    ggplot2::geom_text(
      data = callout_df,
      ggplot2::aes(
        x = .fitted,
        y = .actual,
        label = sprintf("%s (%+.2f)", model, .resid)
      ),
      color = TELEMETRY_ALERT,
      size = 2.65,
      fontface = "bold",
      vjust = ifelse(callout_df$.resid >= 0, -1.0, 1.6),
      check_overlap = TRUE
    ) +
    ggplot2::scale_color_manual(name = "Cyl", values = CYL_PALETTE, drop = TRUE) +
    ggplot2::coord_cartesian(xlim = lims, ylim = lims) +
    ggplot2::labs(
      title    = "Actual vs. Predicted",
      subtitle = "Dashed 1:1 line · Largest absolute residual callouts highlighted",
      x        = paste0("Predicted ", var_label(response_var)),
      y        = paste0("Actual ", var_label(response_var)),
      caption  = formula_str
    ) +
    theme_telemetry(base_size = 10)
}

make_residuals_plot <- function(aug_df, response_var, rse = NA_real_) {
  if (is.null(aug_df) || nrow(aug_df) == 0) {
    return(make_empty_plot("No residual diagnostics available"))
  }

  aug_df$cyl_factor <- factor(aug_df$cyl, levels = c(4, 6, 8))
  aug_df$abs_resid <- abs(aug_df$.resid)
  top_k <- min(3L, nrow(aug_df))
  callout_df <- aug_df[order(-aug_df$abs_resid), , drop = FALSE][seq_len(top_k), , drop = FALSE]

  p <- ggplot2::ggplot(aug_df, ggplot2::aes(x = .fitted, y = .resid))

  if (is.finite(rse) && rse > 0) {
    p <- p +
      ggplot2::geom_hline(
        yintercept = c(-2 * rse, 2 * rse),
        linetype = "dotted",
        color = "#475569",
        linewidth = 0.55
      )
  }

  p <- p +
    ggplot2::geom_hline(
      yintercept = 0,
      linetype = "dashed",
      color = TELEMETRY_SUB,
      linewidth = 0.65
    )

  if (nrow(aug_df) >= 7) {
    p <- p +
      ggplot2::geom_smooth(
        method = "loess",
        formula = y ~ x,
        se = FALSE,
        color = TELEMETRY_ACCENT,
        linewidth = 0.75,
        span = 0.9
      )
  }

  p +
    ggplot2::geom_point(
      ggplot2::aes(color = cyl_factor),
      size = 2.9,
      alpha = 0.92
    ) +
    ggplot2::geom_text(
      data = callout_df,
      ggplot2::aes(x = .fitted, y = .resid, label = model),
      color = TELEMETRY_ALERT,
      size = 2.65,
      fontface = "bold",
      vjust = ifelse(callout_df$.resid >= 0, -1.0, 1.6),
      check_overlap = TRUE
    ) +
    ggplot2::scale_color_manual(name = "Cyl", values = CYL_PALETTE, drop = TRUE) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.14, 0.16))) +
    ggplot2::labs(
      title    = "Residuals vs. Fitted",
      subtitle = "Zero-error reference · Dotted lines mark +/- 2 RSE · Cyan trend = LOESS",
      x        = paste0("Fitted ", var_label(response_var)),
      y        = "Residual (Actual - Fitted)",
      caption  = if (is.finite(rse)) sprintf("Residual Std. Error = %.3f", rse) else NULL
    ) +
    theme_telemetry(base_size = 10)
}
