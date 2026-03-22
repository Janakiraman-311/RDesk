# RDesk (v1.0.0)

[![R-CMD-check](https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml)
[![build-app](https://github.com/Janakiraman-311/RDesk/actions/workflows/build-app.yml/badge.svg)](https://github.com/Janakiraman-311/RDesk/actions/workflows/build-app.yml)

**The Enterprise-Grade Native Desktop Framework for R.**

RDesk enables R developers to build standalone Windows desktop applications with professional web-based UIs (HTML/CSS/JS). Powered by a zero-port native IPC bridge and WebView2, it bypasses the network stack entirely for maximum security and performance.

| Feature | Details |
|---|---|
| **Zero-Port Security** | No `httpuv` or open ports. Uses native PostWebMessage bridge. |
| **Async Performance** | Multi-tier background tasks via `mirai` and `callr`. |
| **Native Integration** | Win32 Menus, System Tray, Toast Notifications, and File Dialogs. |
| **Zero Config** | One-click scaffolding creates a professional "Hero" Dashboard. |
| **Easy Distribution** | Single ZIP or InnoSetup Installer with bundled R runtime. |

## 🚀 Quick Start

### 1. Install RDesk
```r
# Note: Requires Windows 10/11 and Rtools44+
devtools::install_github("Janakiraman-311/RDesk")
```

### 2. Scaffold Your "Hero" Dashboard
RDesk includes a professional, card-based dashboard template with integrated sidebar filters and async plot rendering.
```r
library(RDesk)
rdesk_create_app("MyDashboard", path = "C:/Projects")
```

### 3. Build & Ship
Distribute your app as a professional Windows installer.
```r
# Tip: Use dry_run = TRUE to validate your structure in < 1 second!
RDesk::build_app(
  app_dir         = "C:/Projects/MyDashboard",
  app_name        = "SalesDash",
  build_installer = TRUE
)
```

## ⚡ Powerhouse Features

### 🌪️ Async-First Logic
Stop blocking your UI. Use the `async()` wrapper to run heavy R logic (like model training or large plots) in the background with automatic loading overlays and error handling.

```r
app$on_message("run_analytics", async(function(payload) {
  # This runs in a background mirai worker
  mtcars %>% 
    filter(cyl == payload$cyl) %>% 
    lm(mpg ~ wt, data = .) %>% 
    broom::tidy()
}, loading_message = "Analyzing data..."))
```

### 🛠️ Professional Build Engine
The `build_app()` engine automatically:
- Provisions a portable R runtime for the target machine.
- Compiles the native C++ launcher on-the-fly.
- Bundles all your HTML/JS/CSS assets.
- Generates a Windows Explorer-ready `.zip` or `.exe` installer.

## 📖 Deeper Documentation
- [**Getting Started**](vignettes/getting-started.Rmd) — Your first 5 minutes with RDesk.
- [**Async Guide**](vignettes/async-guide.Rmd) — Mastering the three-tier background task system.
- [**IPC Contract**](vignettes/ipc-contract.Rmd) — Details on the zero-port messaging bridge.
- [**Architecture**](vignettes/architecture.Rmd) — How the native C++ launcher manages R.

## 🔧 Requirements
- Windows 10 or 11
- [Rtools44+](https://cran.r-project.org/bin/windows/Rtools/) (Required for build compilation)
- [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/) (Built into Windows 11)

---
**RDesk** is maintained by Janakiraman G. Built for R developers who need to ship real software.

## License
MIT
