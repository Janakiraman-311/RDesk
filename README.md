# RDesk

[![R-CMD-check](https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml)
[![build-app](https://github.com/Janakiraman-311/RDesk/actions/workflows/build-app.yml/badge.svg)](https://github.com/Janakiraman-311/RDesk/actions/workflows/build-app.yml)

**The Enterprise-Grade Desktop Framework for R.**

RDesk is a state-of-the-art framework for building standalone Windows applications using R and modern web technologies (HTML/CSS/JS). Unlike Shiny, RDesk apps run with **Zero Network Ports** open, using high-performance native IPC and WebView2.

## 🚀 Key Pillars

- **Zero-Port Security**: No `httpuv` server. Communication happens over native stdin/stdout pipes, making it ideal for high-security enterprise and pharmaceutical environments.
- **Virtual Hostname Mapping**: Assets are served via the internal `https://app.rdesk/` protocol through WebView2's virtual host API—never touching the network stack.
- **Standalone Portability**: Bundle your application with a self-contained R runtime. Distribute as a single ZIP or a professional Windows Installer (.exe)—no R installation required on the target machine.
- **Deep OS Integration**: 
    - Full control over native Win32 Menus and System Tray.
    - Native File Open/Save dialogs and System Notifications.
    - Automatic RTools discovery and C++ launcher compilation.

## ✨ High-Performance Async (Phase 19 & 20)

RDesk is built for speed. With the latest updates, it features a sophisticated background task engine:
- **Persistent Daemon Pool**: Uses `mirai` to pre-warm R workers, achieving a **3.4x speedup** in task latency. Tasks start in <50ms.
- **`async()` Tier 1 Wrapper**: Zero-configuration async handling. Wrap any handler with `async()` and RDesk handles worker isolation, package reloading, loading states, and result routing automatically.
- **Intelligent Fallback**: Seamlessly switches between `mirai` and `callr` based on environment availability, ensuring stability in CI/CD and production.

## ✨ Coming from Shiny?

If you already know Shiny, you already know RDesk. Your **R logic remains identical**—you still use `observe`, `reactives`, and data manipulation exactly as you do today. The only difference is the delivery: instead of a browser-based server, RDesk delivers your UI via a high-performance native bridge. You gain professional desktop features (menus, tray icons, offline installers) without learning a new language.

## 📋 Requirements

- **OS**: Windows 10 or Windows 11 (64-bit).
- **R**: R 4.4.0 or higher.
- **Build Tools**: [RTools 4.4](https://cran.r-project.org/bin/windows/Rtools/rtools44/rtools44.html) or higher (required for launcher compilation).
- **Runtime**: [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) (Pre-installed on Win11; manual install may be required for some Win10 versions).

## 📦 Getting Started

### Installation

```r
# Install directly from GitHub
devtools::install_github("Janakiraman-311/RDesk")
```

### Build your first standalone app

1.  **Initialize**: `RDesk::rdesk_create_app("MyDashboard")`
2.  **Develop**: Edit your logic in `app.R` and your UI in `www/index.html`.
3.  **Package**:
    ```r
    RDesk::build_app(
      app_dir  = "path/to/my_app",
      app_name = "CarsAnalyser",
      build_installer = TRUE
    )
    ```

## 🛠 Project Structure

- `R/`: Core R framework logic and IPC handling.
- `inst/`: Templates, JS shims, and C++ launcher stubs.
- `launcher_src/`: High-performance C++ source for the native windowing engine.
- `man/`: Fully synchronized package documentation.
- `vignettes/`: Technical architecture and IPC contract specifications.
- `dist/`: Output folder for ZIP and EXE distributions.

## 🤖 CI/CD Automation

RDesk comes with built-in GitHub Actions workflows:
- **R-CMD-check**: Automated validation on every push.
- **build-app**: Packages your dashboard into a ZIP artifact automatically.
- **release**: Creates a tagged Draft Release with installers attached on version tags.

## License

MIT © 2026 RDesk Team
