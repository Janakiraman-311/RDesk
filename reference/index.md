# Package index

## Scaffold

Create a new RDesk application

- [`rdesk_create_app()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_create_app.md)
  : Create a new RDesk application

## Core application

Create and run desktop application windows

- [`App`](https://janakiraman-311.github.io/RDesk/reference/App.md) :
  Create and launch a native desktop application window from R.
- [`rdesk_service()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_service.md)
  : Service all active RDesk applications
- [`rdesk_is_bundle()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_is_bundle.md)
  : Check if the app is running in a bundled (standalone) environment

## Async engine

Background task execution without blocking the UI

- [`async()`](https://janakiraman-311.github.io/RDesk/reference/async.md)
  : Wrap a message handler to run asynchronously with zero configuration
- [`rdesk_async()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_async.md)
  : Run a task in the background
- [`rdesk_cancel_job()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_cancel_job.md)
  : Cancel a running background job
- [`rdesk_jobs_pending()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_jobs_pending.md)
  : Check if any background jobs are pending
- [`rdesk_jobs_list()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_jobs_list.md)
  : List currently pending background jobs

## Updates

Auto-update your distributed app

- [`rdesk_auto_update()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_auto_update.md)
  : Automatically check for and install app updates

## Build & distribute

Package your app for distribution

- [`build_app()`](https://janakiraman-311.github.io/RDesk/reference/build_app.md)
  : Build a self-contained distributable from an RDesk application

## IPC Communication

Helpers for the standard RDesk message protocol

- [`rdesk_message()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_message.md)
  : Construct a standard RDesk IPC message envelope
- [`rdesk_parse_message()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_parse_message.md)
  : Parse and validate an incoming RDesk IPC message

## Utilities & Serialization

Helpers for plot conversion and data framing

- [`rdesk_plot_to_base64()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_plot_to_base64.md)
  : Convert a ggplot2 object to a base64-encoded PNG string
- [`rdesk_df_to_list()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_df_to_list.md)
  : Convert a data frame to a list suitable for JSON serialization
- [`rdesk_error_plot()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_error_plot.md)
  : Generate a base64-encoded error plot
