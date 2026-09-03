# RDesk

<p align="center">
  <img src="man/figures/logo.png" width="180" alt="RDesk hex logo"/>
</p>

<p align="center">
  <a href="https://CRAN.R-project.org/package=RDesk"><img src="https://www.r-pkg.org/badges/version/RDesk" alt="CRAN status"/></a>
  <a href="https://lifecycle.r-lib.org/articles/stages.html#experimental"><img src="https://img.shields.io/badge/lifecycle-experimental-orange.svg" alt="Lifecycle: experimental"/></a>
  <a href="https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml"><img src="https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml/badge.svg" alt="R-CMD-check"/></a>
  <a href="https://janakiraman-311.github.io/RDesk/"><img src="https://github.com/Janakiraman-311/RDesk/actions/workflows/pkgdown.yaml/badge.svg" alt="pkgdown"/></a>
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"/>
  <img src="https://img.shields.io/badge/platform-Windows-blue" alt="Windows"/>
</p>

<p align="center">
  <strong>Package R analyses into self-contained native desktop applications with zero network port requirements.</strong>
</p>

---

RDesk packages your R analysis into a standalone desktop application for Windows (with future support planned for macOS and Linux). Instead of running an HTTP server and opening a browser tab, RDesk uses a native launcher plus an embedded webview so the app runs offline with local IPC only.

## Quick Start

```r
# Install from CRAN
install.packages("RDesk")

# Scaffold an interactive app
RDesk::rdesk_create_app("MyApp")

# Run it immediately
source("MyApp/app.R")
```

When you are ready to ship:

```r
RDesk::build_app(
  app_dir         = "MyApp",
  app_name        = "MyApp",
  build_installer = TRUE
)

# Windows -> dist/MyApp-1.0.0-setup.exe (or dist/MyApp-1.0.0-windows.zip)
```

Windows produces a standalone installer or portable zip distribution (with macOS and Linux packaging in active development). No separate R installation or browser server is required on the target machine when using the bundled runtime.

> **Development version**
> ```r
> devtools::install_github("Janakiraman-311/RDesk")
> ```

## Why RDesk?

| Feature | Shiny | RInno (archived) | Electron + R | **RDesk** |
|:---|:---:|:---:|:---:|:---:|
| Network ports required | Yes | Yes | Yes | **No** |
| Works fully offline | No | Partial | Partial | **Yes** |
| Native file dialogs and menus | No | No | Via JS | **Yes** |
| Distribution format | Server URL | Installer | Installer | **Bundle or installer** |
| Bundle size | Server-side | 350 MB+ | 350-500 MB | **~200 MB** |
| Skills required | R | R + Electron | R + Node.js | **R only** |

## Core Features

- **Zero-port IPC** - R and the UI communicate through native stdin/stdout pipes and platform webview bindings, without opening network ports.
- **Async by default** - Non-blocking background work using `mirai` and `callr` with support for progress updates, loading states, and cancellation.
- **Version-safe runtime** - `build_app()` bundles a matching R runtime so the shipped app and its packages stay aligned.
- **Modern web UI** - Build the interface with plain HTML, CSS, and JavaScript while keeping the backend in R.
- **Automated scaffolding** - `rdesk_create_app()` generates a working application template with handlers, structure, and theme support.
- **Native packaging** - Produce platform-specific bundles and installers without adopting a browser-server deployment model.

## Who It's For

RDesk is built for R developers who need to package a local statistical or data tool for non-R users.

- **Pharma and clinical** - distribute review or validation tools for offline execution.
- **Consulting** - package analytical models into branded tools without exposing source code.
- **Internal teams** - replace complex spreadsheet macros with structured R applications.
- **Restricted environments** - ship local tools where listening ports are disallowed or heavily scrutinized.

## Example Apps

Two apps ship with RDesk demonstrating different complexity levels.

**CarsAnalyser** - minimal dashboard

```r
app_dir <- system.file("apps/mtcars_dashboard", package = "RDesk")
source(file.path(app_dir, "app.R"))
```

**Data Intelligence Studio** - full-featured data profiling tool

```r
app_dir <- system.file("apps/data_studio", package = "RDesk")
source(file.path(app_dir, "app.R"))
```

## Documentation

Full documentation is available at [janakiraman-311.github.io/RDesk](https://janakiraman-311.github.io/RDesk/).

| Guide | What it covers |
|:---|:---|
| [Getting Started](https://janakiraman-311.github.io/RDesk/articles/getting-started.html) | From `install.packages()` to your first native app |
| [Coming from Shiny](https://janakiraman-311.github.io/RDesk/articles/shiny-migration.html) | Side-by-side mapping of common Shiny patterns to RDesk |
| [Async Guide](https://janakiraman-311.github.io/RDesk/articles/async-guide.html) | Background tasks, progress overlays, cancellation |
| [Cookbook](https://janakiraman-311.github.io/RDesk/articles/cookbook.html) | Practical desktop-app recipes |
| [Why RDesk?](https://janakiraman-311.github.io/RDesk/articles/rdesk-article.html) | Project background and architecture |

## License

MIT (c) Janakiraman G.
