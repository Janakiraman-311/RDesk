# tests/manual/test_phase8_multi.R
# Test Multi-Window and System Tray support
 
devtools::load_all(".")
 
# Window 1: Main Control
app1 <- App$new(title = "Primary Window", width = 800, height = 600)
 
app1$on_ready(function() {
  app1$set_tray(
    label = "RDesk Controller",
    on_click = function(btn) {
      message("[Tray] Clicked with: ", btn)
      app1$notify("Tray Click", paste("You used the", btn, "mouse button"))
    }
  )
})
 
# Window 2: Secondary View
app2 <- App$new(title = "Secondary Window", width = 400, height = 300)
 
# Launch both non-blocking
app1$run(block = FALSE)
app2$run(block = FALSE)
 
message("[Test] Both windows launched. Managing from single R thread...")
 
# Run our own service loop for 30 seconds
start_time <- Sys.time()
while (as.numeric(difftime(Sys.time(), start_time, units = "secs")) < 30) {
  rdesk_service()
  Sys.sleep(0.01)
}
 
message("[Test] Done.")
