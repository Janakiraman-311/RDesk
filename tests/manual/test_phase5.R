# tests/manual/test_phase5.R
devtools::load_all()

# Build the demo dashboard into a distributable zip
# Use R 4.5.1 since that's what we are using locally
zip_path <- build_app(
  app_dir  = "inst/apps/mtcars_dashboard",
  out_dir  = "dist",
  app_name = "CarsAnalyser",
  version  = "1.0.0",
  r_version = "4.5.1",
  overwrite = TRUE
)

cat("Output:", zip_path, "\n")

# Verify zip contents
# Note: we need the zip package for this
if (!requireNamespace("zip", quietly = TRUE)) install.packages("zip")
contents <- zip::zip_list(zip_path)
cat("Files in zip:", nrow(contents), "\n")

# Check key files exist inside zip
key_files <- c("CarsAnalyser.exe",
                "bin/rdesk-launcher.exe",
                "runtime/R/bin/x64/Rscript.exe",
                "app/app.R")
for (f in key_files) {
  rel_paths <- contents$filename
  # Match either exact or with folder prefix
  found <- any(grepl(f, rel_paths, fixed = TRUE))
  cat(ifelse(found, "[OK]", "[MISSING]"), f, "\n")
}
