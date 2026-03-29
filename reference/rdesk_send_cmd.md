# Send a JSON command to the launcher process over stdin

Send a JSON command to the launcher process over stdin

## Usage

``` r
rdesk_send_cmd(proc, cmd, payload = list(), id = NULL)
```

## Arguments

- proc:

  Process object

- cmd:

  Command string (e.g., "QUIT", "SET_MENU")

- payload:

  Data to send as JSON

- id:

  Optional request ID for async responses
