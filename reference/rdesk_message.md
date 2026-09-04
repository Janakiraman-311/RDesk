# Construct a standard RDesk IPC message envelope

Builds the JSON envelope that both R and the JavaScript frontend use to
exchange typed messages. Each envelope carries a unique ID, a message
type string, a contract version, an arbitrary payload, and a
millisecond-precision Unix timestamp.

## Usage

``` r
rdesk_message(
  type,
  payload = list(),
  version = getOption("rdesk.ipc_version", "1.0")
)
```

## Arguments

- type:

  Character string. The message type / action name (e.g. `"get_data"`).

- payload:

  A named list representing the message data. Defaults to an empty list.

- version:

  IPC contract version string. Defaults to the `rdesk.ipc_version`
  option (currently `"1.0"`).

## Value

A named list representing the standard JSON envelope. Pass this directly
to
[`jsonlite::toJSON()`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html)
or to `app$send()`.

## Details

The envelope schema is:


      {
        "id":        "msg_<epoch_ms>_<random>",
        "type":      "<action_name>",
        "version":   "1.0",
        "payload":   { ... },
        "timestamp": <unix_seconds>
      }

Large payloads (above 1 MB) trigger a warning so developers notice
performance-sensitive serialization early.

## See also

[`rdesk_parse_message()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_parse_message.md)
for the corresponding deserializer.

## Examples

``` r
# Construct a typed message with a simple payload
msg <- rdesk_message("get_data", list(filter = "cyl == 6"))
stopifnot(msg$type == "get_data")
stopifnot(msg$version == "1.0")
stopifnot(!is.null(msg$id))
```
