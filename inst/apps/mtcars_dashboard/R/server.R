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
    
    job_id <- rdesk_async(
      task = function(e) {
        # Source all app-level helpers in the child process
        r_dir <- file.path(e$app_dir, "R")
        if (dir.exists(r_dir)) {
          lapply(list.files(r_dir, pattern = "\\.R$", full.names = TRUE), source)
        }
        
        library(dplyr)
        library(ggplot2)
        library(base64enc)
        Sys.sleep(0.5)
        
        # Use found helpers directly
        p <- make_plot(e$filtered, e$x_var, e$y_var)
        list(
          kpis  = kpis(e$filtered),
          chart = plot_to_b64(p),
          table = e$filtered %>%
            dplyr::select(model, mpg, hp, wt, cyl, gear) %>%
            head(15)
        )
      },
      args = list(e = as.list(env)),
      on_done = function(result) {
        app$loading_done()
        app$send("data_update", result)
        app$toast("Plot updated.", type = "success", duration_ms = 1500L)
      },
      on_error = function(err) {
        app$loading_done()
        app$toast(paste("Error:", err$message), type = "error")
      }
    )
    app$loading_start("Updating plot...", cancellable = TRUE, job_id = job_id)
  })

  app$on_message("set_cyl_filter", function(msg) {
    env$cyl_filter <- as.numeric(unlist(msg$cyls))
    # Note: If env$cyl_filter is empty, the async task will correctly return 0 rows.
    
    job_id <- rdesk_async(
      task = function(e) {
        # Source all app-level helpers in the child process
        r_dir <- file.path(e$app_dir, "R")
        if (dir.exists(r_dir)) {
          lapply(list.files(r_dir, pattern = "\\.R$", full.names = TRUE), source)
        }
        
        library(dplyr)
        library(ggplot2)
        library(base64enc)
        Sys.sleep(0.8)
        
        # Apply filters in background
        filtered <- e$df[e$df$cyl %in% e$cyl_filter, ]
        
        p <- make_plot(filtered, e$x_var, e$y_var)
        list(
          filtered = filtered,
          kpis     = kpis(filtered),
          chart    = plot_to_b64(p),
          table    = filtered %>%
            dplyr::select(model, mpg, hp, wt, cyl, gear) %>%
            head(15)
        )
      },
      args = list(e = as.list(env)),
      on_done = function(result) {
        env$filtered <- result$filtered
        app$loading_done()
        app$send("data_update", result)
        app$toast("Filter applied.", type = "success", duration_ms = 1500L)
      },
      on_error = function(err) {
        app$loading_done()
        app$toast(paste("Error:", err$message), type = "error")
      }
    )
    app$loading_start("Filtering cars...", cancellable = TRUE, job_id = job_id)
  })

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
