# All ggplot2 chart functions for Data Intelligence Studio

make_overview_chart <- function(df, missing_info) {
  # Missing value bar chart — first thing shown after load
  if (nrow(missing_info) == 0 || all(missing_info$pct_missing == 0)) {
    p <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5, size = 5,
                        label = "No missing values detected",
                        colour = "#1D9E75") +
      ggplot2::theme_void()
  } else {
    top_missing <- head(missing_info[missing_info$pct_missing > 0, ], 15)
    top_missing$variable <- factor(top_missing$variable,
                                    levels = rev(top_missing$variable))

    p <- ggplot2::ggplot(top_missing,
           ggplot2::aes(x = variable, y = pct_missing)) +
      ggplot2::geom_col(fill = "#E74C3C", alpha = 0.8) +
      ggplot2::coord_flip() +
      ggplot2::theme_minimal(base_size = 12) +
      ggplot2::labs(
        title = "Missing Values by Variable",
        x     = NULL,
        y     = "Missing (%)"
      ) +
      ggplot2::theme(plot.title = ggplot2::element_text(
        size = 13, face = "bold"))
  }
  rdesk_plot_to_base64(p, width = 9, height = 5)
}

make_distribution_charts <- function(df) {
  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
  num_cols <- head(num_cols, 9)  # max 9 charts in a 3x3 grid

  if (length(num_cols) == 0) {
    p <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5, size = 5,
                        label = "No numeric columns available for distribution analysis.",
                        colour = "#E74C3C") +
      ggplot2::theme_void()
    return(rdesk_plot_to_base64(p, width = 12, height = 8))
  }

  df_long <- do.call(rbind, lapply(num_cols, function(col) {
    data.frame(variable = col, value = df[[col]][!is.na(df[[col]])])
  }))

  p <- ggplot2::ggplot(df_long, ggplot2::aes(x = value)) +
    ggplot2::geom_histogram(fill = "#378ADD", colour = "white",
                             bins = 30, alpha = 0.8) +
    ggplot2::facet_wrap(~ variable, scales = "free") +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::labs(title = "Variable Distributions", x = NULL, y = "Count") +
    ggplot2::theme(
      strip.text   = ggplot2::element_text(face = "bold"),
      plot.title   = ggplot2::element_text(size = 13, face = "bold")
    )

  rdesk_plot_to_base64(p, width = 12, height = 8)
}

make_correlation_chart <- function(df, method = "pearson") {
  num_df  <- df[, vapply(df, is.numeric, logical(1)), drop = FALSE]
  if (ncol(num_df) < 2) {
    p <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5, size = 5,
                        label = "Need at least 2 numeric columns for correlation analysis.",
                        colour = "#E74C3C") +
      ggplot2::theme_void()
    return(rdesk_plot_to_base64(p, width = 10, height = 8))
  }

  corr_mat <- cor(num_df, use = "pairwise.complete.obs", method = method)

  corr_df  <- as.data.frame(as.table(corr_mat))
  colnames(corr_df) <- c("Var1", "Var2", "value")

  p <- ggplot2::ggplot(corr_df,
         ggplot2::aes(x = Var1, y = Var2, fill = value)) +
    ggplot2::geom_tile(colour = "white", linewidth = 0.5) +
    ggplot2::geom_text(ggplot2::aes(
      label = round(value, 2)),
      size  = 3, colour = "white") +
    ggplot2::scale_fill_gradient2(
      low      = "#E74C3C",
      mid      = "white",
      high     = "#2ECC71",
      midpoint = 0,
      limits   = c(-1, 1)
    ) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(
      axis.text.x  = ggplot2::element_text(angle = 45, hjust = 1),
      plot.title   = ggplot2::element_text(size = 13, face = "bold")
    ) +
    ggplot2::labs(
      title = "Correlation Matrix",
      x     = NULL,
      y     = NULL,
      fill  = "r"
    )

  rdesk_plot_to_base64(p, width = 10, height = 8)
}

make_outlier_chart <- function(df, outlier_table) {
  num_cols <- outlier_table$variable[outlier_table$n_outliers > 0]
  if (length(num_cols) == 0) {
    p <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0.5, y = 0.5, size = 5,
                        label = "No outliers detected in numeric columns.",
                        colour = "#1D9E75") +
      ggplot2::theme_void()
    return(rdesk_plot_to_base64(p, width = 10, height = 6))
  }
  num_cols <- head(num_cols, 6)

  df_long <- do.call(rbind, lapply(num_cols, function(col) {
    data.frame(variable = col, value = df[[col]][!is.na(df[[col]])])
  }))

  p <- ggplot2::ggplot(df_long,
         ggplot2::aes(x = variable, y = value)) +
    ggplot2::geom_boxplot(fill = "#9B59B6", alpha = 0.7,
                           outlier.colour = "#E74C3C",
                           outlier.size   = 2) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::labs(
      title = "Outlier Detection (IQR method)",
      x     = NULL,
      y     = "Value"
    ) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 30, hjust = 1),
      plot.title  = ggplot2::element_text(size = 13, face = "bold")
    )

  rdesk_plot_to_base64(p, width = 10, height = 6)
}
