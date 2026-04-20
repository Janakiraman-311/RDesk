# RDesk AI Skill: Shiny to RDesk Conversion Guide

You are an expert AI assistant specializing in R programming and the RDesk package.
Your task is to help the user convert their existing R Shiny applications into native Windows desktop applications using the RDesk framework.

## 1. The Core Paradigm Shift
Shiny is a **reactive framework** based on a reactive graph (`reactive()`, `observe()`, `render*()`).
RDesk is an **event-driven, message-passing framework**. There is no automatic reactivity. The UI (JavaScript/HTML) explicitly sends messages to the R backend, and the R backend explicitly returns payloads or sends messages back.

**Shiny:**
```r
observeEvent(input$btn, {
  output$plot <- renderPlot({ plot(cars) })
})
```

**RDesk:**
```r
# R Backend
app$on_message("btn_clicked", function(payload) {
  list(plot_data = rdesk_plot_to_base64(plot(cars)))
})

# JavaScript Frontend
rdesk.send("btn_clicked", {}).then((result) => {
  document.getElementById("img").src = result.plot_data;
});
```

## 2. Handlers and Routing
Instead of a `server(input, output, session)` function, RDesk uses an `App` R6 object with explicit message listeners registered via `app$on_message("event_name", handler_function)`.

*   Payloads from JavaScript arrive as R lists.
*   The return value of the handler function is automatically serialized to JSON and sent back to the JavaScript `Promise` that initiated the request.

## 3. UI and Frontend
Shiny generates HTML via R functions (e.g., `fluidPage`, `sliderInput`).
RDesk relies on standard web technologies: HTML, CSS, and JavaScript. You must rewrite the Shiny UI into standard HTML/JS, optionally using frameworks like Bootstrap, React, or standard vanilla JS.
All UI assets should be stored in the `www/` directory.

## 4. Long-Running Tasks (Async)
Shiny handles long-running tasks via `future` and `promises`.
RDesk has a built-in asynchronous engine powered by `mirai`. Wrap your handler in `async()` to execute it in the background without blocking the UI.

**Shiny (future):**
```r
future({ slow_calc() }) %...>% (function(res) output$val <- renderText(res))
```

**RDesk (async):**
```r
app$on_message("run_calc", async(function(payload) {
  sys.sleep(5)
  list(result = 42)
}, app = app, loading_message = "Calculating..."))
```
The `async()` wrapper automatically displays a loading overlay in the UI and handles promise resolution.

## 5. File System and Dialogs
Shiny uses `downloadHandler` and `fileInput`.
RDesk uses native Windows dialogs tied directly to the application window.

*   `app$dialog_save(title = "Save CSV", filters = "CSV files (*.csv)|*.csv")`
*   `app$dialog_open(title = "Open Data")`
*   `app$dialog_folder(title = "Select Folder")`

**Example:**
```r
app$on_message("export_data", function(payload) {
  path <- app$dialog_save("Save file", "CSV (*.csv)|*.csv")
  if (!is.null(path)) {
    write.csv(my_data, path, row.names = FALSE)
  }
})
```

## 6. Native Menus and Window Management
RDesk allows native Win32 window integration which Shiny cannot perform.
*   **Menus:** Replace Shiny sidebars with native menus using `app$set_menu()`.
*   **System Tray:** Use `app$set_tray_menu()` and `app$notify()` for background notifications.
*   **Window State:** Control the layout with `app$maximize()`, `app$minimize()`, `app$fullscreen()`.

## 7. Migration Checklist for AI:
1.  **Extract Data Logic:** Separate the pure R data-processing functions from Shiny's `reactive()` contexts.
2.  **Map Inputs/Outputs to IPC:** Create a mapping of all Shiny `input$X` and `output$Y` to RDesk IPC messages.
3.  **Create HTML/JS UI:** Build a frontend equivalent of the Shiny UI in `www/index.html` and `www/app.js`.
4.  **Implement Handlers:** Write `app$on_message()` handlers for every UI action. Replace `renderPlot` with `rdesk_plot_to_base64()`, and `renderTable` with `rdesk_df_to_list()`.
5.  **Replace File I/O:** Swap `fileInput`/`downloadHandler` with `app$dialog_open()` and `app$dialog_save()`.
6.  **Apply Async:** Identify slow steps and wrap their handlers in `async()`.

Always verify that R code accessing `app$*` methods is executing inside the main thread, or carefully passed via `async()` configurations.
