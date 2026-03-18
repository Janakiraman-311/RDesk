# Manual performance test — run locally, not in CI
devtools::load_all(".")

# Simple task function
task_fn <- function(x) {
  # Simulate very light work
  x * 2
}

message("\n--- RDesk Async Performance Benchmark ---")
message("Testing 5 sequential tasks to measure startup overhead difference.\n")

# 1. Benchmark callr
message("[1/2] Benchmarking 'callr' backend (spawning per task)...")
options(rdesk.async_backend = "callr")
t_callr <- system.time({
  for (i in 1:5) {
    done <- FALSE
    rdesk_async(task_fn, args = list(x = i),
      on_done = function(r) { done <<- TRUE },
      on_error = function(e) { message("Error: ", e$message); done <<- TRUE }
    )
    # Busy wait for polling (simulating the app event loop)
    while (!done) { 
      rdesk_poll_jobs()
      Sys.sleep(0.01) 
    }
  }
})

# 2. Benchmark mirai
message("[2/2] Benchmarking 'mirai' backend (persistent daemon pool)...")
options(rdesk.async_backend = "mirai")
# Manually start daemons for the test (usually handled by App$run)
mirai::daemons(2) 
t_mirai <- system.time({
  for (i in 1:5) {
    done <- FALSE
    rdesk_async(task_fn, args = list(x = i),
      on_done = function(r) { done <<- TRUE },
      on_error = function(e) { message("Error: ", e$message); done <<- TRUE }
    )
    while (!done) { 
      rdesk_poll_jobs()
      Sys.sleep(0.01) 
    }
  }
})
mirai::daemons(0) # Shutdown daemons

# Results
callr_elapsed <- t_callr["elapsed"]
mirai_elapsed <- t_mirai["elapsed"]
speedup       <- callr_elapsed / mirai_elapsed

message("\n--- RESULTS ---")
message("callr 5 tasks: ", round(callr_elapsed, 2), "s")
message("mirai 5 tasks: ", round(mirai_elapsed, 2), "s")
message("Startup Speedup: ", round(speedup, 1), "x")
message("------------------------------------------\n")

if (speedup > 2) {
  message("SUCCESS: mirai significantly reduces task latency.")
} else {
  message("NOTE: Speedup less than 2x, check system load or config.")
}
