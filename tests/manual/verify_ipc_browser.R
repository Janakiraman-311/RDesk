# tests/manual/verify_ipc_browser.R
library(devtools)
load_all("c:/Users/Janak/OneDrive/Documents/RDesk/RDesk", recompile = FALSE)

# Use a fixed port for the browser test if possible, or just print it
port <- 54321 

app <- App$new(
  title  = "IPC Browser Verification",
  www    = system.file("templates", "hello", "www", package = "RDesk")
)

# During development fallback
if (app$.__enclos_env__$private$.www == "") {
  app$.__enclos_env__$private$.www <- file.path(getwd(), "inst", "templates", "hello", "www")
}

app$on_message("ping", function(msg) {
  message("[R] Received ping: ", jsonlite::toJSON(msg))
  app$send("pong", list(server_time = format(Sys.time())))
})

app$on_message("get_data", function(msg) {
  message("[R] Received get_data")
  app$send("data_result", list(nrow = 32, cols = c("mpg", "cyl")))
})

# We'll run the server for a fixed time or until a signal
app$on_ready(function() {
  message("VERIFY_URL: http://127.0.0.1:", port, "/?__rdesk_port__=", port)
})

# Override the random port for this test
# We'll monkeypatch rdesk_free_port or just set it in run()
# For simplicity, let's just let it be random and I'll catch the output.

app$run()
