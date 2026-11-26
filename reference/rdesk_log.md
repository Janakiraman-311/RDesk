# Log a message to the app's log file

Log a message to the app's log file

## Usage

``` r
rdesk_log(
  message,
  level = "INFO",
  app_name = Sys.getenv("R_APP_NAME", "RDeskApp")
)
```

## Arguments

- message:

  Message to log

- level:

  Log level ("INFO", "WARN", "ERROR")

- app_name:

  Optional app name to determine log file
