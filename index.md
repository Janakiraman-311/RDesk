# RDesk

![RDesk hex logo](reference/figures/logo.png)

[![CRAN
status](https://www.r-pkg.org/badges/version/RDesk)](https://CRAN.R-project.org/package=RDesk)
[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml)
[![pkgdown](https://github.com/Janakiraman-311/RDesk/actions/workflows/pkgdown.yaml/badge.svg)](https://janakiraman-311.github.io/RDesk/)
![MIT
license](https://img.shields.io/badge/license-MIT-blue.svg)![Windows](https://img.shields.io/badge/platform-Windows-blue)

**Package R analyses into self-contained desktop applications with
native webviews.**

------------------------------------------------------------------------

RDesk packages your R analysis into a standalone desktop application for
Windows (with future support planned for macOS and Linux). Instead of
running an HTTP server and opening a browser tab, RDesk uses a native
launcher plus an embedded webview so the app runs offline with local IPC
only.

## Quick Start

``` r

# Install from CRAN
install.packages("RDesk")

# Scaffold an interactive app
RDesk::rdesk_create_app("MyApp")

# Run it immediately
source("MyApp/app.R")
```

When you are ready to ship:

``` r

RDesk::build_app(
  app_dir         = "MyApp",
  app_name        = "MyApp",
  build_installer = TRUE
)

# Windows -> dist/MyApp-1.0.0-setup.exe (or dist/MyApp-1.0.0-windows.zip)
```

Windows produces a standalone installer or portable zip distribution
(with macOS and Linux packaging in active development). No separate R
installation or browser server is required on the target machine when
using the bundled runtime.

> **Development version**
>
> ``` r
>
> devtools::install_github("Janakiraman-311/RDesk")
> ```

## How RDesk Compares

There are different architectures for deploying and distributing R
applications depending on your needs:

| Deployment Model | Typical Use Case | Frontend Layer | Backend Communication | Distribution & Footprint |
|:---|:---|:---|:---|:---|
| **Hosted Shiny** (Posit Connect, shinyapps.io) | Multi-user web applications & dashboards | Shiny reactive UI (pure R DSL) | Centralized R server over WebSocket | Web URL (no local install required) |
| **Electron + Shiny** (e.g. electricShine, DesktopDeployR) | Desktop wrapper around existing Shiny apps | Shiny reactive UI in embedded Chromium | Local R server on loopback port | Installer / bundle (~400–600 MB) |
| **WebR / Shinylive** | Serverless in-browser execution | Shiny reactive UI in browser | R compiled to WebAssembly (client-side) | Static web hosting (no native OS access) |
| **RDesk** | Standalone local desktop tools | Standard web frontend (HTML/CSS/JS) | Local R process via native IPC pipes | Standalone bundle or installer (~100–200 MB) |

### When to choose RDesk vs. Shiny

- **Choose Shiny** if you want to write your UI entirely in R using
  reactive expressions, or if your application will primarily be
  deployed on a shared server or web portal.
- **Choose RDesk** if you want to ship a self-contained desktop app with
  a smaller footprint (leveraging the operating system’s native webview
  rather than bundling Chromium), or need direct desktop integration
  (native menus, file pickers) without running a local web server. Note
  that RDesk uses an event-driven model (messages passed between HTML/JS
  and R handlers) rather than a reactive graph.

## Core Features

- **Zero-port IPC** - R and the UI communicate through native
  stdin/stdout pipes and platform webview bindings, without opening
  network ports.
- **Async by default** - Non-blocking background work using `mirai` and
  `callr` with support for progress updates, loading states, and
  cancellation.
- **Version-safe runtime** -
  [`build_app()`](https://janakiraman-311.github.io/RDesk/reference/build_app.md)
  bundles a matching R runtime so the shipped app and its packages stay
  aligned.
- **Modern web UI** - Build the interface with plain HTML, CSS, and
  JavaScript while keeping the backend in R.
- **Automated scaffolding** -
  [`rdesk_create_app()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_create_app.md)
  generates a working application template with handlers, structure, and
  theme support.
- **Native packaging** - Produce platform-specific bundles and
  installers without adopting a browser-server deployment model.

## Who It’s For

RDesk is built for R developers who need to package a local statistical
or data tool for non-R users.

- **Pharma and clinical** - distribute review or validation tools for
  offline execution.
- **Consulting** - package analytical models into branded tools without
  exposing source code.
- **Internal teams** - replace complex spreadsheet macros with
  structured R applications.
- **Restricted environments** - ship local tools where listening ports
  are disallowed or heavily scrutinized.

## Example Apps

Two apps ship with RDesk demonstrating different complexity levels.

**CarsAnalyser** - minimal dashboard

``` r

app_dir <- system.file("apps/mtcars_dashboard", package = "RDesk")
source(file.path(app_dir, "app.R"))
```

**Data Intelligence Studio** - full-featured data profiling tool

``` r

app_dir <- system.file("apps/data_studio", package = "RDesk")
source(file.path(app_dir, "app.R"))
```

## Documentation

Full documentation is available at
[janakiraman-311.github.io/RDesk](https://janakiraman-311.github.io/RDesk/).

| Guide | What it covers |
|:---|:---|
| [Getting Started](https://janakiraman-311.github.io/RDesk/articles/getting-started.html) | From [`install.packages()`](https://rdrr.io/r/utils/install.packages.html) to your first native app |
| [Coming from Shiny](https://janakiraman-311.github.io/RDesk/articles/shiny-migration.html) | Side-by-side mapping of common Shiny patterns to RDesk |
| [Async Guide](https://janakiraman-311.github.io/RDesk/articles/async-guide.html) | Background tasks, progress overlays, cancellation |
| [Cookbook](https://janakiraman-311.github.io/RDesk/articles/cookbook.html) | Practical desktop-app recipes |
| [Why RDesk?](https://janakiraman-311.github.io/RDesk/articles/rdesk-article.html) | Project background and architecture |

## License

MIT (c) Janakiraman G.
