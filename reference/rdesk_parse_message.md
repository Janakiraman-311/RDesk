# Parse and validate an incoming RDesk IPC message

Parse and validate an incoming RDesk IPC message

## Usage

``` r
rdesk_parse_message(raw_json)
```

## Arguments

- raw_json:

  The raw JSON string from the frontend

## Value

A list containing the validated message components, or NULL if invalid
