# RDesk

The first native desktop app framework for R.

## Installation

```r
# Install from source
install.packages("RDesk", repos = NULL, type = "source")
```

## Usage

```r
library(RDesk)
app <- App$new(title = "My App")
app$on_ready(function() {
  message("App is ready")
})
app$run()
```
