# tests/manual/test_phase18.R
# Manual verification for Phase 18: Loading & Toasts

# Find project root (assume it's 2 levels up from here)
script_dir <- getwd()
if (basename(script_dir) == "manual") script_dir <- dirname(dirname(script_dir))
if (file.exists("DESCRIPTION")) {
  devtools::load_all(".")
} else {
  # Try to find RDesk folder if run from USER folder
  potential_root <- file.path(getwd(), "OneDrive/Documents/RDesk")
  if (dir.exists(potential_root)) {
    setwd(potential_root)
    devtools::load_all(".")
  } else {
    stop("Could not find RDesk project root. Please cd to the project directory.")
  }
}

# Create a demo app instance
app <- App$new(title = "Phase 18 Verification")

app$on_ready(function() {
  # Small delay for bridge to be ready
  Sys.sleep(1)
  
  rscript <- file.path(R.home("bin"), "Rscript.exe")
  if (!file.exists(rscript)) rscript <- "Rscript"

  app$toast("Phase 18 Verified: UI Bridge is Live!", type = "info")
  Sys.sleep(1)
  
  dummy_job <- "verify_job_123"
  app$loading_start(
    message     = "Processing background task...", 
    cancellable = TRUE, 
    job_id      = dummy_job
  )
  
  processx::run(rscript, c("-e", "Sys.sleep(1)"))
  app$loading_progress(30, "Still working...")
  
  processx::run(rscript, c("-e", "Sys.sleep(1)"))
  app$loading_progress(70, "Almost there...")
  
  processx::run(rscript, c("-e", "Sys.sleep(1)"))
  
  app$loading_done()
  app$toast("Verification sequence complete!", type = "success")
})

# Run the app
# Note: In a real terminal, this will open the window.
app$run()
