# Construct a standard RDesk IPC message envelope

Construct a standard RDesk IPC message envelope

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

  The message type/action name

- payload:

  A list representing the message data

- version:

  The contract version (default "1.0")

## Value

A list representing the standard JSON envelope
