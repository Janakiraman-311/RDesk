# RDesk

[![R-CMD-check](https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml)
[![build-app](https://github.com/Janakiraman-311/RDesk/actions/workflows/build-app.yml/badge.svg)](https://github.com/Janakiraman-311/RDesk/actions/workflows/build-app.yml)
[![pkgdown](https://github.com/Janakiraman-311/RDesk/actions/workflows/pkgdown.yaml/badge.svg)](https://janakiraman-311.github.io/RDesk/)

**Build native Windows desktop applications with R.**

RDesk turns your R code into a standalone .exe that runs on any
Windows machine - no R installation required. Zero open network ports.
Native Win32 window. Ships as a single ZIP or professional installer.

```r
# Install
devtools::install_github("Janakiraman-311/RDesk")

# Create a working dashboard app in one line
RDesk::rdesk_create_app("MySalesReport")
```

## Why RDesk

| | Shiny | RDesk |
|---|---|---|
| Delivery | Browser + server | Native .exe |
| Network ports | Yes (httpuv) | **Zero** |
| Offline use | No | **Yes** |
| Distribute as | Deploy to server | **ZIP or installer** |
| Feels like | A website | Excel / Tableau |
| R knowledge required | Full R | **Full R + 7 new concepts** |

## What you get from one command

```r
RDesk::rdesk_create_app("MyApp")
```

- Working dashboard with real data loaded on first run
- Native Win32 menu (File, Help)
- async() background processing already wired up
- Loading overlay with progress and cancel
- Light or dark theme
- Ready to build and distribute immediately

## Requirements

- Windows 10 or 11
- R 4.2 or later
- [Rtools44+](https://cran.r-project.org/bin/windows/Rtools/)
- [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)
  (pre-installed on Windows 11)

## Distribute your app

```r
RDesk::build_app(
  app_dir         = "MyApp",
  app_name        = "MyApp",
  build_installer = TRUE
)
# Output: dist/MyApp-1.0.0-setup.exe
# Send to anyone on Windows. No R required on their machine.
```

## Documentation

Full documentation at **[janakiraman-311.github.io/RDesk](https://janakiraman-311.github.io/RDesk/)**

- [Get started](https://janakiraman-311.github.io/RDesk/articles/getting-started.html)
- [Coming from Shiny](https://janakiraman-311.github.io/RDesk/articles/shiny-migration.html)
- [Async guide](https://janakiraman-311.github.io/RDesk/articles/async-guide.html)
- [Cookbook](https://janakiraman-311.github.io/RDesk/articles/cookbook.html)

## License

MIT
