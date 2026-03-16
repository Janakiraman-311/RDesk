# inst/apps/mtcars_dashboard/app.R
# Motor Trend Cars Analyser — RDesk demo dashboard

library(RDesk)
library(ggplot2)
library(dplyr)

# ── data ──────────────────────────────────────────────────────────────────────
.env <- new.env(parent = emptyenv())
.env$df      <- mtcars %>% mutate(model = rownames(mtcars), .before = 1)
.env$filtered <- .env$df
.env$x_var   <- "wt"
.env$y_var   <- "mpg"
.env$cyl_filter <- c(4, 6, 8)

# ── helpers ───────────────────────────────────────────────────────────────────
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
    ggplot2::geom_smooth(method = "lm", se = TRUE,
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

kpis <- function(df) {
  list(
    n        = nrow(df),
    mean_mpg = round(mean(df$mpg, na.rm = TRUE), 1),
    mean_hp  = round(mean(df$hp, na.rm = TRUE),  1),
    mean_wt  = round(mean(df$wt, na.rm = TRUE) * 1000, 0)  # lbs
  )
}

apply_filters <- function() {
  .env$filtered <- .env$df %>%
    dplyr::filter(cyl %in% .env$cyl_filter)
}

push_update <- function(app) {
  df <- .env$filtered
  app$send("data_update", list(
    kpis  = kpis(df),
    chart = plot_to_b64(make_plot(df, .env$x_var, .env$y_var)),
    table = df %>%
      select(model, mpg, hp, wt, cyl, gear) %>%
      head(15)
  ))
}

# ── app ───────────────────────────────────────────────────────────────────────
# Robustly find the app directory
app_dir <- if (nzchar(Sys.getenv("R_BUNDLE_APP"))) {
  # In a bundle, the launcher runs from AppRoot. 
  # Files are in AppRoot/app/
  file.path(getwd(), "app")
} else {
  # In development
  tryCatch({
    res <- dirname(rstudioapi::getActiveDocumentContext()$path)
    if (!nzchar(res)) stop()
    res
  }, error = function(e) {
    # Fallback to current dir if it looks correct
    if (dir.exists("www")) getwd() else getwd() 
  })
}

# Final fallback for development in RDesk project
if (!dir.exists(file.path(app_dir, "www"))) {
  dev_path <- file.path(getwd(), "inst/apps/mtcars_dashboard")
  if (dir.exists(dev_path)) app_dir <- dev_path
}

app <- App$new(
  title  = "Motor Trend Cars Analyser — RDesk",
  width  = 1100,
  height = 740,
  www    = file.path(app_dir, "www")
)

# ── message handlers ──────────────────────────────────────────────────────────
app$on_message("ready", function(msg) {
  push_update(app)
})

app$on_message("set_axes", function(msg) {
  if (!is.null(msg$x)) .env$x_var <- msg$x
  if (!is.null(msg$y)) .env$y_var <- msg$y
  push_update(app)
})

app$on_message("set_cyl_filter", function(msg) {
  .env$cyl_filter <- as.numeric(unlist(msg$cyls))
  if (length(.env$cyl_filter) == 0) .env$cyl_filter <- c(4, 6, 8)
  apply_filters()
  push_update(app)
})

app$on_message("load_csv", function(msg) {
  path <- app$dialog_open(
    title   = "Load vehicle data CSV",
    filters = list("CSV files" = "*.csv")
  )
  if (!is.null(path)) {
    tryCatch({
      new_df          <- read.csv(path, stringsAsFactors = FALSE)
      new_df$model    <- if ("model" %in% names(new_df)) new_df$model else rownames(new_df)
      .env$df         <- new_df
      apply_filters()
      push_update(app)
      app$notify("Data loaded", paste0(nrow(new_df), " rows from ", basename(path)))
    }, error = function(e) {
      app$send("error_msg", list(msg = paste("Failed to load:", e$message)))
    })
  }
})

app$on_message("export_csv", function(msg) {
  path <- app$dialog_save(
    title        = "Export filtered data",
    default_name = "rdesk_export.csv",
    filters      = list("CSV files" = "*.csv")
  )
  if (!is.null(path)) {
    write.csv(.env$filtered, path, row.names = FALSE)
    app$notify("Export complete", paste0(nrow(.env$filtered), " rows saved to ", basename(path)))
  }
})

# ── menu ──────────────────────────────────────────────────────────────────────
app$on_ready(function() {
  app$set_menu(list(
    File = list(
      "Load CSV"      = function() app$send("__trigger__", list(action = "load_csv")),
      "Export CSV"    = function() app$send("__trigger__", list(action = "export_csv")),
      "---",
      "Exit"          = app$quit
    ),
    View = list(
      "Reset filters" = function() {
        .env$cyl_filter <- c(4, 6, 8)
        .env$x_var      <- "wt"
        .env$y_var      <- "mpg"
        apply_filters()
        push_update(app)
        app$send("reset_ui", list())
      }
    ),
    Help = list(
      "About RDesk"   = function() {
        app$notify("RDesk v0.1.0",
                   "The first native desktop app framework for R")
      }
    )
  ))
})

app$run()
