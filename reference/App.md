# Create and launch a native desktop application window from R.

Provides bidirectional native pipe communication between R and the UI.

## Methods

### Public methods

- [`App$new()`](#method-App-new)

- [`App$on_ready()`](#method-App-on_ready)

- [`App$on_close()`](#method-App-on_close)

- [`App$check_update()`](#method-App-check_update)

- [`App$register_hotkey()`](#method-App-register_hotkey)

- [`App$set_tray_menu()`](#method-App-set_tray_menu)

- [`App$clipboard_write()`](#method-App-clipboard_write)

- [`App$clipboard_read()`](#method-App-clipboard_read)

- [`App$on_message()`](#method-App-on_message)

- [`App$send()`](#method-App-send)

- [`App$load_ui()`](#method-App-load_ui)

- [`App$set_size()`](#method-App-set_size)

- [`App$set_position()`](#method-App-set_position)

- [`App$set_title()`](#method-App-set_title)

- [`App$minimize()`](#method-App-minimize)

- [`App$maximize()`](#method-App-maximize)

- [`App$restore()`](#method-App-restore)

- [`App$fullscreen()`](#method-App-fullscreen)

- [`App$always_on_top()`](#method-App-always_on_top)

- [`App$set_menu()`](#method-App-set_menu)

- [`App$dialog_open()`](#method-App-dialog_open)

- [`App$dialog_save()`](#method-App-dialog_save)

- [`App$dialog_folder()`](#method-App-dialog_folder)

- [`App$message_box()`](#method-App-message_box)

- [`App$dialog_color()`](#method-App-dialog_color)

- [`App$notify()`](#method-App-notify)

- [`App$loading_start()`](#method-App-loading_start)

- [`App$loading_progress()`](#method-App-loading_progress)

- [`App$loading_done()`](#method-App-loading_done)

- [`App$toast()`](#method-App-toast)

- [`App$set_tray()`](#method-App-set_tray)

- [`App$remove_tray()`](#method-App-remove_tray)

- [`App$service()`](#method-App-service)

- [`App$quit()`](#method-App-quit)

- [`App$get_dir()`](#method-App-get_dir)

- [`App$run()`](#method-App-run)

- [`App$clone()`](#method-App-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new RDesk application

#### Usage

    App$new(title, width = 1200L, height = 800L, www = NULL, icon = NULL)

#### Arguments

- `title`:

  Window title string

- `width`:

  Window width in pixels (default 1200)

- `height`:

  Window height in pixels (default 800)

- `www`:

  Directory containing HTML/CSS/JS assets (default: built-in template)

- `icon`:

  Path to window icon file

#### Returns

A new App instance

------------------------------------------------------------------------

### Method `on_ready()`

Register a callback to fire when the window is ready

#### Usage

    App$on_ready(fn)

#### Arguments

- `fn`:

  A zero-argument function called after the server starts and window
  opens

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `on_close()`

Register a callback to fire when the user attempts to close the window

#### Usage

    App$on_close(fn)

#### Arguments

- `fn`:

  A zero-argument function. Should return TRUE to allow closing, FALSE
  to cancel.

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `check_update()`

Check for application updates from a remote URL

#### Usage

    App$check_update(version_url, current_version = NULL)

#### Arguments

- `version_url`:

  URL to a JSON metadata file (e.g.
  `{"version": "1.1.0", "url": "http://..."}`)

- `current_version`:

  Optional version string to compare against. Defaults to app
  description version.

#### Returns

A list with update status and metadata

------------------------------------------------------------------------

### Method `register_hotkey()`

Register a global keyboard shortcut (hotkey)

#### Usage

    App$register_hotkey(keys, fn)

#### Arguments

- `keys`:

  Character string representing the key combination (e.g.,
  "Ctrl+Shift+A")

- `fn`:

  A zero-argument function to be called when the hotkey is pressed

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `set_tray_menu()`

Set the native system tray menu

#### Usage

    App$set_tray_menu(items)

#### Arguments

- `items`:

  A named list of lists defining the menu structure

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `clipboard_write()`

Write text to the system clipboard

#### Usage

    App$clipboard_write(text)

#### Arguments

- `text`:

  Character string to copy

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `clipboard_read()`

Read text from the system clipboard

#### Usage

    App$clipboard_read()

#### Returns

Character string from clipboard or NULL

------------------------------------------------------------------------

### Method `on_message()`

Register a handler for a UI -\> R message type

#### Usage

    App$on_message(type, fn)

#### Arguments

- `type`:

  Unique message identifier string

- `fn`:

  A function(payload) called when this message type arrives

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `send()`

Send a message from R to the UI

#### Usage

    App$send(type, payload = list())

#### Arguments

- `type`:

  Character string message type (received by rdesk.on() in JS)

- `payload`:

  A list or data.frame to serialise as JSON payload

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `load_ui()`

Load an HTML file into the window

#### Usage

    App$load_ui(path = "index.html")

#### Arguments

- `path`:

  Path relative to the www directory (e.g. "index.html")

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `set_size()`

Set the window size dynamically

#### Usage

    App$set_size(width, height)

#### Arguments

- `width`:

  New width (pixels)

- `height`:

  New height (pixels)

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `set_position()`

Set the window position dynamically

#### Usage

    App$set_position(x, y)

#### Arguments

- `x`:

  Horizontal position from left (pixels)

- `y`:

  Vertical position from top (pixels)

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `set_title()`

Set the window title dynamically

#### Usage

    App$set_title(title)

#### Arguments

- `title`:

  New title

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `minimize()`

Minimize the window to the taskbar

#### Usage

    App$minimize()

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `maximize()`

Maximize the window to fill the screen

#### Usage

    App$maximize()

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `restore()`

Restore the window from minimize/maximize

#### Usage

    App$restore()

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `fullscreen()`

Toggle fullscreen mode

#### Usage

    App$fullscreen(enabled = TRUE)

#### Arguments

- `enabled`:

  If TRUE, enters fullscreen. If FALSE, exits.

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `always_on_top()`

Set the window to stay always on top of others

#### Usage

    App$always_on_top(enabled = TRUE)

#### Arguments

- `enabled`:

  If TRUE, always on top.

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `set_menu()`

Set the native window menu

#### Usage

    App$set_menu(items)

#### Arguments

- `items`:

  A named list of lists defining the menu structure

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `dialog_open()`

Open a native file-open dialog

#### Usage

    App$dialog_open(title = "Open File", filters = NULL)

#### Arguments

- `title`:

  Dialog title

- `filters`:

  List of file filters, e.g. list("CSV files" = "\*.csv")

#### Returns

Selected file path (character) or NULL if cancelled

------------------------------------------------------------------------

### Method `dialog_save()`

Open a native file-save dialog

#### Usage

    App$dialog_save(title = "Save File", default_name = "", filters = NULL)

#### Arguments

- `title`:

  Dialog title

- `default_name`:

  Initial filename

- `filters`:

  List of file filters

#### Returns

Selected file path (character) or NULL if cancelled

------------------------------------------------------------------------

### Method `dialog_folder()`

Open a native folder selection dialog

#### Usage

    App$dialog_folder(title = "Select Folder")

#### Arguments

- `title`:

  Dialog title

#### Returns

Selected directory path (character) or NULL if cancelled

------------------------------------------------------------------------

### Method `message_box()`

Show a native message box / alert

#### Usage

    App$message_box(message, title = "RDesk", type = "ok", icon = "info")

#### Arguments

- `message`:

  The message text

- `title`:

  The dialog title

- `type`:

  One of "ok", "okcancel", "yesno", "yesnocancel"

- `icon`:

  One of "info", "warning", "error", "question"

#### Returns

The button pressed (character: "ok", "cancel", "yes", "no")

------------------------------------------------------------------------

### Method `dialog_color()`

Open a native color selection dialog

#### Usage

    App$dialog_color(initial_color = "#FFFFFF")

#### Arguments

- `initial_color`:

  Optional hex color to start with (e.g. "#FF0000")

#### Returns

Selected hex color code or NULL if cancelled

------------------------------------------------------------------------

### Method `notify()`

Send a native desktop notification

#### Usage

    App$notify(title, body = "")

#### Arguments

- `title`:

  Notification title

- `body`:

  Notification body text

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `loading_start()`

Show a loading state in the UI

#### Usage

    App$loading_start(
      message = "Loading...",
      progress = NULL,
      cancellable = FALSE,
      job_id = NULL
    )

#### Arguments

- `message`:

  Text shown under the spinner

- `progress`:

  Optional numeric 0-100 for a progress bar

- `cancellable`:

  If TRUE, shows a cancel button in the UI

- `job_id`:

  Optional job_id from rdesk_async() to wire cancel button

------------------------------------------------------------------------

### Method `loading_progress()`

Update progress on an active loading state

#### Usage

    App$loading_progress(value, message = NULL)

#### Arguments

- `value`:

  Numeric 0-100

- `message`:

  Optional updated message

------------------------------------------------------------------------

### Method `loading_done()`

Hide the loading state in the UI

#### Usage

    App$loading_done()

------------------------------------------------------------------------

### Method `toast()`

Show a non-blocking toast notification in the UI

#### Usage

    App$toast(message, type = "info", duration_ms = 3000L)

#### Arguments

- `message`:

  Text to show

- `type`:

  One of "info", "success", "warning", "error"

- `duration_ms`:

  How long to show it (default 3000ms)

------------------------------------------------------------------------

### Method `set_tray()`

Set or update the system tray icon

#### Usage

    App$set_tray(label = "RDesk App", icon = NULL, on_click = NULL)

#### Arguments

- `label`:

  Tooltip text for the tray icon

- `icon`:

  Path to .ico file (optional)

- `on_click`:

  Character "left" or "right" or callback function(button)

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `remove_tray()`

Remove the system tray icon

#### Usage

    App$remove_tray()

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `service()`

Service this app's pending native events

#### Usage

    App$service()

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method [`quit()`](https://rdrr.io/r/base/quit.html)

Close the window and stop the app's event loop.

#### Usage

    App$quit()

#### Returns

The App instance (invisible)

------------------------------------------------------------------------

### Method `get_dir()`

Get the application root directory (where www/ and R/ are located).

#### Usage

    App$get_dir()

#### Returns

Character string path.

------------------------------------------------------------------------

### Method `run()`

Start the application - opens the window

#### Usage

    App$run(block = TRUE)

#### Arguments

- `block`:

  If TRUE (default), blocks with an event loop until the window is
  closed.

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    App$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Examples

``` r
# Safe logical check (unwrapped)
app_dir <- system.file("templates/hello", package = "RDesk")
if (nzchar(app_dir)) {
  message("Built-in app directory: ", app_dir)
}
#> Built-in app directory: C:/Users/runneradmin/AppData/Local/R/cache/R/renv/library/RDesk-47d971e3/windows/R-4.5/x86_64-w64-mingw32/RDesk/templates/hello

if (interactive()) {
  app <- App$new(title = "Car Visualizer", width = 1200, height = 800)
  
  app$on_ready(function() {
    message("App is ready!")
  })
  
  # Handle messages from UI
  app$on_message("get_data", function(payload) {
    list(cars = mtcars[1:5, ])
  })
  
  # Start the app
  app$run()
}
```
