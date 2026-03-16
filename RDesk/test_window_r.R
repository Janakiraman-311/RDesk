library(devtools)
load_all("c:/Users/Janak/OneDrive/Documents/RDesk/RDesk", recompile = FALSE)

message("Testing rdesk_open_window...")
proc <- rdesk_open_window("https://www.google.com", "R Test Window", 800, 600)

if (proc$is_alive()) {
  message("Success: Window process is alive.")
  Sys.sleep(3)
  message("Closing window...")
  rdesk_close_window(proc)
  message("Success: Window closed.")
} else {
  stop("Failure: Window process is not alive.")
}
