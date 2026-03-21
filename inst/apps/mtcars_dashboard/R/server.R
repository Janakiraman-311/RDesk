# inst/apps/mtcars_dashboard/R/server.R
# Message handlers and UI events

push_update <- function(app, env) {
  df <- env$filtered
  # Sourcing local helpers since they aren't in a package
  lapply(list.files(file.path(env$app_dir, "R"), pattern = "\\.R$", full.names = TRUE), source)
  
  app$send("data_update", list(
    kpis    = kpis(df),
    chart   = plot_to_b64(make_plot(df, env$x_var, env$y_var, env$plot_type)),
    summary = summary_stats(df),
    table   = df %>%
      dplyr::select(model, mpg, hp, wt, cyl) %>%
      head(15)
  ))
}

init_handlers <- function(app, env) {
  # -- navigation -----------------------------------------------------------
  # We use a simple section switcher in the UI
  app$on_message("nav", function(msg) {
    app$send("switch_section", list(section = msg$target))
  })

  # -- explorer -------------------------------------------------------------
  app$on_message("ready", function(msg) {
    push_update(app, env)
  })

  app$on_message("set_cyl_filter", async(function(msg) {
    env$cyl_filter <- as.numeric(unlist(msg$cyls))
    apply_filters(env)
    
    # Sourcing local helpers
    lapply(list.files(file.path(env$app_dir, "R"), pattern = "\\.R$", full.names = TRUE), source)
    
    list(
      kpis    = kpis(env$filtered),
      chart   = plot_to_b64(make_plot(env$filtered, env$x_var, env$y_var, env$plot_type)),
      summary = summary_stats(env$filtered),
      table   = env$filtered %>%
        dplyr::select(model, mpg, hp, wt, cyl) %>%
        head(15)
    )
  }, app = app, loading_message = "Filtering cars..."))

  app$on_message("toggle_plot_type", function(msg) {
    env$plot_type <- msg$type
    push_update(app, env)
  })

  # -- models ---------------------------------------------------------------
  app$on_message("run_model", async(function(payload) {
    # Full linear model
    model  <- lm(mpg ~ wt + cyl + hp, data = mtcars)
    model_summary <- summary(model)
    result <- as.data.frame(model_summary$coefficients)
    result$term <- rownames(result)
    rownames(result) <- NULL
    names(result) <- c("estimate", "std.error", "statistic", "p.value", "term")
    
    # Result for UI
    list(
      coefficients = result,
      r_squared    = round(model_summary$r.squared, 3),
      formula      = "mpg ~ wt + cyl + hp"
    )
  }, app = app, loading_message = "Fitting model..."))

  # -- export ---------------------------------------------------------------
  app$on_message("export_csv", function(msg) {
    path <- app$dialog_save(
      title        = "Export mtcars data",
      default_name = "rdesk_export.csv",
      filters      = list("CSV files" = "*.csv")
    )
    if (!is.null(path)) {
      write.csv(env$filtered, path, row.names = FALSE)
      app$toast(paste("Exported to", basename(path)), type = "success")
    }
  })

  # -- menu -----------------------------------------------------------------
  app$on_ready(function() {
    app$set_menu(list(
      File = list(
        "Reset App"     = function() {
          init_data(env)
          push_update(app, env)
          app$toast("App state reset", type = "info")
        },
        "---",
        "Exit"          = app$quit
      ),
      Section = list(
        "Explorer"      = function() app$send("__trigger__", list(action = "nav", target = "explorer")),
        "Models"        = function() app$send("__trigger__", list(action = "nav", target = "models")),
        "Export"        = function() app$send("__trigger__", list(action = "nav", target = "export"))
      ),
      Help = list(
        "About RDesk"   = function() {
          app$toast("RDesk v1.0.0: The native desktop framework for R.", type = "info")
        }
      )
    ))
  })
}
