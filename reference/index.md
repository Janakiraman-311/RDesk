# Package index

## Scaffold

Create a new RDesk application from a professional template.

- [`rdesk_create_app()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_create_app.md)
  : Create a new RDesk application

## Core Application

Create, configure, and run native desktop application windows.

- [`App`](https://janakiraman-311.github.io/RDesk/reference/App.md) :
  Create and launch a native desktop application window from R.
- [`rdesk_service()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_service.md)
  : Service all active RDesk applications
- [`rdesk_is_bundle()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_is_bundle.md)
  : Check if the app is running in a bundled (standalone) environment

## Developer Velocity

Live hot reloading of R modules and UI code.

- [`rdesk_watch()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_watch.md)
  : Enable live hot reloading for an RDesk application

## Async Engine

Run background tasks without freezing the UI - built on mirai.

- [`async()`](https://janakiraman-311.github.io/RDesk/reference/async.md)
  : Wrap a message handler to run asynchronously with zero configuration
- [`async_progress()`](https://janakiraman-311.github.io/RDesk/reference/async_progress.md)
  : Update progress of a background async task
- [`rdesk_async()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_async.md)
  : Run a task in the background
- [`rdesk_cancel_job()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_cancel_job.md)
  : Cancel a running background job
- [`rdesk_jobs_pending()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_jobs_pending.md)
  : Check if any background jobs are pending
- [`rdesk_jobs_list()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_jobs_list.md)
  : List currently pending background jobs

## Multi-User Storage

Isolated JSON-backed key-value stores mapping dynamically to user and
system folders.

- [`RDeskStorage`](https://janakiraman-311.github.io/RDesk/reference/RDeskStorage.md)
  : RDesk Storage Manager
- [`rdesk_storage()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_storage.md)
  : Create a multi-user storage manager

## Auto-Update

Keep distributed apps up to date automatically.

- [`rdesk_auto_update()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_auto_update.md)
  : Automatically check for and install app updates

## Build & Distribute

Package your app into a self-contained ZIP or Windows installer.

- [`build_app()`](https://janakiraman-311.github.io/RDesk/reference/build_app.md)
  : Build a self-contained distributable from an RDesk application

## IPC Communication

Low-level helpers for the RDesk message envelope protocol.

- [`rdesk_message()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_message.md)
  : Construct a standard RDesk IPC message envelope
- [`rdesk_parse_message()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_parse_message.md)
  : Parse and validate an incoming RDesk IPC message

## Utilities & Serialisation

Convert plots and data frames for transport over the IPC bridge.

- [`rdesk_plot_to_base64()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_plot_to_base64.md)
  : Convert a ggplot2 object to a base64-encoded PNG string
- [`rdesk_df_to_list()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_df_to_list.md)
  : Convert a data frame to a list suitable for JSON serialization
- [`rdesk_error_plot()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_error_plot.md)
  : Generate a base64-encoded error plot
