# build_test_fix.R
cat("Starting RDesk build verification (Phase 24 Fixes)...\n")
library(R6)
library(jsonlite)
library(processx)
library(base64enc)
library(ggplot2)
library(dplyr)
library(digest)
library(zip)

# Source all R files
r_files <- list.files("R", full.names = TRUE)
for (f in r_files) {
  cat("Sourcing: ", f, "\n")
  source(f)
}

cat("All files sourced. Starting build_app...\n")
tryCatch({
  build_app(
    app_dir  = "inst/apps/mtcars_dashboard",
    out_dir  = "dist_test_fix",
    app_name = "CarsPrunedFix",
    prune_runtime = TRUE,
    overwrite = TRUE
  )
  cat("\nBUILD SUCCESSFUL!\n")
}, error = function(e) {
  cat("\nBUILD FAILED:\n")
  print(e)
  quit(status = 1)
})
