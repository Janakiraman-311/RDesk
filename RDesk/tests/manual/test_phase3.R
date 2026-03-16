# tests/manual/test_phase3.R
library(devtools)
load_all("c:/Users/Janak/OneDrive/Documents/RDesk/RDesk", recompile = FALSE)

app <- App$new(title = "Phase 3 Native Features", width = 900, height = 650)

app$on_ready(function() {
  message("[R] Setting up menu...")
  
  # Define the menu structure
  # Note: The launcher handles list(Label = list("Item" = fn, ...))
  app$set_menu(list(
    File = list(
      "Open file" = function() {
        message("[R] Opening dialog...")
        path <- app$dialog_open(
          title   = "Choose a CSV",
          filters = list("CSV files" = "*.csv", "Text files" = "*.txt")
        )
        if (!is.null(path)) {
          message("[R] User chose: ", path)
          app$send("log", list(msg = paste("Loaded:", path)))
        } else {
          message("[R] User cancelled dialog")
        }
      },
      "Save output" = function() {
        path <- app$dialog_save(
          title        = "Save result",
          default_name = "output.csv"
        )
        if (!is.null(path)) {
          message("[R] Save to: ", path)
          app$send("log", list(msg = paste("Saving to:", path)))
        }
      },
      "---",
      "Exit" = app$quit
    ),
    Help = list(
      "About" = function() {
        app$notify("RDesk", "Version 0.1.0 — the first native R desktop framework")
      }
    )
  ))

  app$notify("RDesk", "Phase 3 test app is ready")
  message("[R] App ready. Test the menu bar and dialogs.")
})

# Add a simple handler for logging messages from R to UI if needed
# For now we'll just use the default hello template which shows messages in log
app$on_message("ping", function(msg) {
  app$send("log", list(msg = "Pong from R"))
})

app$on_message("get_data", function(msg) {
  app$send("data_result", list(nrow = 32, cols = c("mpg", "cyl")))
})

app$on_message("get_time", function(msg) {
  app$send("time_result", list(time = format(Sys.time())))
})

app$run()
