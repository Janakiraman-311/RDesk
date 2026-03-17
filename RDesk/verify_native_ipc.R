# verify_native_ipc.R
library(devtools)
# Load the project from the current directory
load_all(".")

# Navigate to the app directory so that app.R find its local files
setwd("inst/apps/mtcars_dashboard")

# Source the app
source("app.R")
