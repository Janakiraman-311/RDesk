# RDesk

[![R-CMD-check](https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml)
[![build-app](https://github.com/Janakiraman-311/RDesk/actions/workflows/build-app.yml/badge.svg)](https://github.com/Janakiraman-311/RDesk/actions/workflows/build-app.yml)

**The native desktop application framework for R.**

RDesk lets R developers build standalone Windows desktop applications
using R and modern web technologies (HTML/CSS/JS). Apps run with
zero open network ports using native WebView2 and stdin/stdout IPC.
Distribute as a single ZIP or professional Windows installer.
No R installation required on the end user's machine.

## Why RDesk?

If you can write a Shiny app, you can build a desktop app with RDesk.
Your R logic — dplyr, ggplot2, models — stays identical.
RDesk replaces the browser delivery mechanism with a native Windows
window, giving your users a true desktop experience with no server,
no browser, and no internet connection required.

| | Shiny | RDesk |
|---|---|---|
| Delivery | Browser + server | Native exe |
| Network ports | Yes — httpuv | Zero |
| R on client | Not needed | Not needed |
| Offline use | No | Yes |
| Feels like | A website | Excel / Tableau |
| Target | Web dashboards | Desktop software |

## Key features

- **Zero-port security** — PostWebMessage IPC replaces httpuv entirely.
  No open ports. Passes enterprise security audits.
- **Virtual hostname** — Assets served via `https://app.rdesk/`
  through WebView2's virtual host API. Never touches the network stack.
- **Async engine** — Three-tier background task system (async wrapper,
  rdesk_async, mirai direct). 5.9x faster than per-task process spawning.
  Loading overlays, progress bars, and cancellation built in.
- **Native OS integration** — Win32 menus, system tray, file dialogs,
  toast notifications.
- **Standalone distribution** — Bundle portable R runtime automatically.
  Distribute as ZIP or InnoSetup installer exe.
- **Professional CI/CD** — Three GitHub Actions workflows: check,
  build, and release with draft installer attached.

## Requirements

- Windows 10 or 11
- [Rtools44+](https://cran.r-project.org/bin/windows/Rtools/) for building
- [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)
  (pre-installed on Windows 11, download for Windows 10)

## Installation

```r
devtools::install_github("Janakiraman-311/RDesk")
```

## Your first app

```r
# Create a new app scaffold
RDesk::rdesk_create_app("MyDashboard", path = "C:/Projects")
```

Edit `R/server.R`:

```r
app$on_message("greet", async(function(payload) {
  list(message = paste("Hello from R,", payload$name))
}))
```

Edit `www/js/app.js`:

```javascript
rdesk.send("greet", { name: "World" });
rdesk.on("greet_result", function(data) {
  document.getElementById("output").textContent = data.message;
});
```

Build and distribute:

```r
RDesk::build_app(
  app_dir         = "C:/Projects/MyDashboard",
  app_name        = "MyDashboard",
  build_installer = TRUE
)
# Output: dist/MyDashboard-1.0.0-setup.exe
# No R installation required on the target machine.
```

If you already have a usable R runtime on the build machine, you can
skip the portable-R download step:

```r
RDesk::build_app(
  app_dir     = "C:/Projects/MyDashboard",
  app_name    = "MyDashboard",
  runtime_dir = "C:/Program Files/R/R-4.5.1"
)
```

If you want CI or an advanced local setup to opt into the legacy
installer-based runtime expansion explicitly, use:

```r
RDesk::build_app(
  app_dir            = "C:/Projects/MyDashboard",
  app_name           = "MyDashboard",
  portable_r_method  = "installer"
)
```

For reproducible team builds, this repo now supports `renv`. If the
project root contains `renv.lock`, GitHub Actions restores that locked
environment before running checks or bundled-app builds. Each bundle
created with `build_app()` also writes its own `renv.lock` and a
`restore_env.R` helper into the distributable root when `renv` is
available on the build machine.

## Async in one line

```r
# Runs in background, shows spinner, routes result automatically
app$on_message("run_model", async(function(payload) {
  lm(mpg ~ wt + cyl, data = mtcars) |> broom::tidy()
}))
```

## Project structure

```
RDesk/
├── R/              Core framework — App R6, IPC, async engine
├── launcher_src/   C++ native launcher source
├── inst/           Templates, JS bridge, demo apps, installer script
├── man/            Roxygen documentation
├── vignettes/      IPC contract, async guide, architecture
└── tests/          Unit and manual tests
```

## CI/CD

Every push to main triggers automated validation and build.
Version tags trigger a draft release with the installer attached.
The bundled-app workflows use `portable_r_method = "installer"` so CI
does not depend on a standalone 7-Zip installation.
When `renv.lock` is present, CI restores the locked project library
before package checks and bundle creation.

```bash
git tag v1.0.0
git push origin v1.0.0
# GitHub builds installer and creates draft release automatically
```

## License

MIT
