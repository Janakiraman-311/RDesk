# Converting a Shiny App to RDesk: Mapping Guide

This document breaks down how to convert the **TS Domain Creator** Shiny app into a native **RDesk** application.

## 1. The Strategy
We separate the **Visuals** from the **Logic**. 
-   **Visuals**: Move from `fluidPage` to a clean **HTML file** using Tailwind CSS for a premium, custom look.
-   **Logic**: Move from `server <- function(input, output)` to an **R6 Class** (`App`) using `on_message` handlers.

---

## 2. Component Mapping

| Shiny Component | RDesk (HTML / JS) | RDesk (R Backend) |
| :--- | :--- | :--- |
| `textInput("studyID")` | `<input id="studyID">` | Accessed via `payload$studyID` |
| `checkboxInput("useDate")` | `<input type="checkbox">` | Accessed via `payload$useDate` |
| `conditionalPanel(...)` | JS function with `classList.toggle('hidden')` | Logic remains client-side (faster!) |
| `actionButton("export")` | `<button onclick="handleExport()">` | Triggers IPC: `rdesk.send('export')` |
| `renderText(status)` | `<div id="status">` | Updated via `app$send('status_result', ...)` |
| `DTOutput("fileTable")` | `<div id="tableContainer">` | R generates HTML string -> JS injects it |

---

## 3. Why RDesk is better for this App:
1.  **Professional UI**: You aren't limited to the standard Bootstrap "sidebar/main" layout. You can use CSS Gradients, Glassmorphism, and custom animations.
2.  **Native Interaction**: Instead of typing `C:/Test`, you can use `app$dialog_open()` to let the user browse their folders natively.
3.  **Portability**: You can use `build_app()` to turn this into a **single .exe folder**. Your users don't need to install R or open a browser; they just click and run.

## 4. How to try the conversion:
I have created the full source code for this converted app in:
`c:/Users/Janak/OneDrive/Documents/RDesk/RDesk/inst/apps/ts_creator/`

To see it in action, open R and run:
```r
devtools::load_all("RDesk")
source("inst/apps/ts_creator/app.R")
```
