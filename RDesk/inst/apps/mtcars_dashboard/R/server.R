# inst/apps/mtcars_dashboard/R/server.R
# Message handlers and UI events

push_update <- function(app, env) {
  df <- env$filtered
  app$send("data_update", list(
    kpis  = kpis(df),
    chart = plot_to_b64(make_plot(df, env$x_var, env$y_var)),
    table = df %>%
      dplyr::select(model, mpg, hp, wt, cyl, gear) %>%
      head(15)
  ))
}

init_handlers <- function(app, env) {
  # ── message handlers ──────────────────────────────────────────────────────────
  app$on_message("ready", function(msg) {
    push_update(app, env)
  })

  app$on_message("set_axes", function(msg) {
    if (!is.null(msg$x)) env$x_var <- msg$x
    if (!is.null(msg$y)) env$y_var <- msg$y
    push_update(app, env)
  })

  app$on_message("set_cyl_filter", function(msg) {
    env$cyl_filter <- as.numeric(unlist(msg$cyls))
    if (length(env$cyl_filter) == 0) env$cyl_filter <- c(4, 6, 8)
    apply_filters(env)
    push_update(app, env)
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
        env$df         <- new_df
        apply_filters(env)
        push_update(app, env)
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
      write.csv(env$filtered, path, row.names = FALSE)
      app$notify("Export complete", paste0(nrow(env$filtered), " rows saved to ", basename(path)))
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
          env$cyl_filter <- c(4, 6, 8)
          env$x_var      <- "wt"
          env$y_var      <- "mpg"
          apply_filters(env)
          push_update(app, env)
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
}
