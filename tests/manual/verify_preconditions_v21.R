# Phase 21 Pre-condition Verification Script
devtools::load_all(".")

# 1. Verify mirai daemon pool lifecycle
cat("--- Testing mirai lifecycle ---\n")
RDesk:::rdesk_start_daemons()
cat("Daemons started. Pending jobs:", RDesk::rdesk_jobs_pending(), "\n")

# 2. Verify async() wrapper logic (Simulated App context)
cat("\n--- Testing async() wrapper ---\n")
# Create a dummy app-like object in global env so async() can find it via parent.frame lookup
app <- list(
  loading_start = function(...) cat("[MockApp] loading_start called\n"),
  loading_done  = function(...) cat("[MockApp] loading_done called\n"),
  send          = function(type, payload) cat("[MockApp] send called with type:", type, "\n"),
  toast         = function(msg, type) cat("[MockApp] toast called:", msg, "(", type, ")\n")
)

# Create a handler using async()
handler <- RDesk::async(function(p) {
  list(res = p$x * 2)
})

# Manually inject type (as App$on_message would do)
attr_env <- attr(handler, "rdesk_msg_type_env")
attr_env$type <- "test_task"

# Run the handler
cat("Running async handler...\n")
job_id <- handler(list(x = 21))
cat("Job launched with ID:", job_id, "\n")

# Wait a bit for result
cat("Waiting for task completion...\n")
Sys.sleep(1.5)
RDesk:::rdesk_poll_jobs() # Trigger polling logic

# 3. Cleanup
RDesk:::rdesk_stop_daemons()
cat("\nDaemons stopped. Pending jobs:", RDesk::rdesk_jobs_pending(), "\n")
cat("--- Verification Complete ---\n")
