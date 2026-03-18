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

  app$on_message("set_axes", async(function(msg) {
    if (!is.null(msg$x)) env$x_var <- msg$x
    if (!is.null(msg$y)) env$y_var <- msg$y
    
    # Sourcing local helpers since they aren't in a package
    lapply(list.files(file.path(env$app_dir, "R"), pattern = "\\.R$", full.names = TRUE), source)
    
    p <- make_plot(env$filtered, env$x_var, env$y_var)
    list(
      kpis  = kpis(env$filtered),
      chart = plot_to_b64(p),
      table = env$filtered %>%
        dplyr::select(model, mpg, hp, wt, cyl, gear) %>%
        head(15)
    )
  }, loading_message = "Updating plot..."))

  app$on_message("set_cyl_filter", async(function(msg) {
    env$cyl_filter <- as.numeric(unlist(msg$cyls))
    
    # Sourcing local helpers
    lapply(list.files(file.path(env$app_dir, "R"), pattern = "\\.R$", full.names = TRUE), source)
    
    # Apply filters
    filtered <- env$df[env$df$cyl %in% env$cyl_filter, ]
    
    p <- make_plot(filtered, env$x_var, env$y_var)
    result <- list(
      filtered = filtered,
      kpis     = kpis(filtered),
      chart    = plot_to_b64(p),
      table    = filtered %>%
        dplyr::select(model, mpg, hp, wt, cyl, gear) %>%
        head(15)
    )
    
    # Side effect in child process doesn't affect parent, 
    # but we return filtered so parent can update its state in on_done if needed.
    # Tier 1 async() result is sent as <type>_result automatically.
    # Note: For Tier 1 to update 'env$filtered', we'd need JS to send it back or 
    # use Tier 2 if we need complex parent state synchronization.
    # However, the user's example showed simple return.
    # I'll add a result handler in JS or keep it as is.
    result
  }, loading_message = "Filtering cars..."))

  app$on_message("load_csv", function(msg) {
    path <- app$dialog_open(
      title   = "Load vehicle data CSV",
      filters = list("CSV files" = "*.csv")
    )
    if (!is.null(path)) {
      tryCatch({
        new_df          <- read.csv(path, stringsAsFactors = FALSE)
        # Validation
        required <- c("mpg", "hp", "wt", "cyl")
        missing  <- setdiff(required, names(new_df))
        if (length(missing) > 0) {
          stop(paste("CSV missing required columns:", paste(missing, collapse = ", ")))
        }
        
        new_df$model    <- if ("model" %in% names(new_df)) new_df$model else rownames(new_df)
        env$df         <- new_df
        apply_filters(env)
        push_update(app, env)
        app$toast(paste("Loaded", nrow(new_df), "rows"), type = "success")
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
      app$toast(paste("Exported", nrow(env$filtered), "rows"), type = "success")
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
          app$toast("RDesk v0.1.0: The first native desktop framework for R.", type = "info")
        }
      )
    ))
  })
}
