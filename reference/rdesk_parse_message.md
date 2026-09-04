# Parse and validate an incoming RDesk IPC message

Deserializes a raw JSON string received from the JavaScript frontend (or
from a bundled launcher via stdin) into a validated R list. Performs
lightweight structural validation: both `type` and `payload` fields must
be present. Launcher/native events (which carry an `event` field
instead) bypass validation and are returned as-is.

## Usage

``` r
rdesk_parse_message(raw_json)
```

## Arguments

- raw_json:

  A single-element character string containing the JSON to parse.

## Value

A named list containing the validated message components, or `NULL` if
the JSON is malformed or the required fields are absent.

## See also

[`rdesk_message()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_message.md)
for constructing outgoing messages.

## Examples

``` r
# Round-trip: construct then parse
msg <- rdesk_message("ping", list(ts = 1234))
raw <- jsonlite::toJSON(msg, auto_unbox = TRUE)
parsed <- rdesk_parse_message(raw)
stopifnot(parsed$type == "ping")

# Malformed JSON returns NULL
stopifnot(is.null(rdesk_parse_message("not_json")))
```
