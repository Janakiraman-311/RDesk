# RDesk

A framework for building native Windows desktop applications using R and modern web technologies.

## Overview

RDesk combines the statistical power of R with the UI flexibility of a WebView2-based architecture. It allows R developers to create standalone, professional-grade desktop software that can be distributed as a simple ZIP file, requiring no R installation on the end-user's machine.

## Key Features

- **Native Windows UI**: Real Win32 windows, menus, and system dialogs.
- **Bi-directional IPC**: Seamless communication between R and JavaScript via WebSockets.
- **Premium Styling**: Build your interface with HTML, CSS, and JS.
- **Standalone Packaging**: Bundle your app with a portable R runtime for zero-dependency distribution.

## Getting Started

### Installation

```r
devtools::install("RDesk")
```

### Building your first app

1. Create an `app.R` and a `www/` directory.
2. Define your logic in R and your UI in HTML/JS.
3. Run or package:

```r
RDesk::build_app(
  app_dir  = "path/to/my_app",
  app_name = "MyDesktopApp"
)
```

## Project Structure

- `R/`: Core R framework logic.
- `inst/`: Bundled assets, templates, and application shims.
- `launcher_src/`: C++ source for the native launcher.
- `man/`: Package documentation.
- `vignettes/`: Technical guides and architecture docs.
- `dist/`: Generated distributable packages (Git ignored).

## License

MIT
