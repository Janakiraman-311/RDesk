# tests/manual/test_phase2.R
# Run with: source("tests/manual/test_phase2.R")

library(devtools)
load_all("c:/Users/Janak/OneDrive/Documents/RDesk/RDesk", recompile = FALSE)

app <- App$new(
  title  = "Phase 2 IPC Test",
  width  = 800,
  height = 600
)

# Wire up all three message handlers
app$on_message("ping", function(msg) {
  cat("[R] Received ping, sending pong\n")
  app$send("pong", list(r_ts = format(Sys.time()), js_ts = msg$ts))
})

app$on_message("get_data", function(msg) {
  cat("[R] Received get_data request\n")
  df <- mtcars
  app$send("data_result", list(
    nrow = nrow(df),
    cols = names(df),
    rows = head(df, 5)
  ))
})

app$on_message("get_time", function(msg) {
  app$send("time_result", list(time = format(Sys.time(), "%H:%M:%S")))
})

app$on_ready(function() {
  cat("[R] App ready. Window opened.\n")
})

app$run()
