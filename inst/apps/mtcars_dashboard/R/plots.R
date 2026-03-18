# inst/apps/mtcars_dashboard/R/plots.R
# Visualization logic

plot_to_b64 <- function(p, w = 820, h = 400) {
  tmp <- tempfile(fileext = ".png")
  on.exit(unlink(tmp))
  ggplot2::ggsave(tmp, plot = p, width = w/96, height = h/96,
                  dpi = 96, device = "png", bg = "white")
  raw  <- readBin(tmp, "raw", file.info(tmp)$size)
  paste0("data:image/png;base64,", base64enc::base64encode(raw))
}

make_plot <- function(df, x, y) {
  ggplot2::ggplot(df, ggplot2::aes(
      x     = .data[[x]],
      y     = .data[[y]],
      color = factor(cyl),
      label = model
    )) +
    ggplot2::geom_point(size = 3.5, alpha = 0.85) +
    ggplot2::geom_smooth(ggplot2::aes(label = NULL), method = "lm", se = TRUE,
                          color = "#2E6DA4", fill = "#D6E8F7", alpha = 0.3) +
    ggplot2::scale_color_manual(
      name   = "Cylinders",
      values = c("4" = "#0F6E56", "6" = "#2E6DA4", "8" = "#993C1D")
    ) +
    ggplot2::labs(
      x       = toupper(x),
      y       = toupper(y),
      caption = paste0("n = ", nrow(df), " vehicles")
    ) +
    ggplot2::theme_minimal(base_size = 13) +
    ggplot2::theme(
      plot.background  = ggplot2::element_rect(fill = "white", color = NA),
      panel.grid.minor = ggplot2::element_blank(),
      legend.position  = "right"
    )
}
