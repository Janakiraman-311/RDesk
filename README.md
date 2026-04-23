# RDesk

<p align="center">
  <img src="man/figures/logo.png" width="180" alt="RDesk hex logo"/>
</p>

<p align="center">
  <a href="https://CRAN.R-project.org/package=RDesk"><img src="https://www.r-pkg.org/badges/version/RDesk" alt="CRAN status"/></a>
  <a href="https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml"><img src="https://github.com/Janakiraman-311/RDesk/actions/workflows/R-CMD-check.yml/badge.svg" alt="R-CMD-check"/></a>
  <a href="https://janakiraman-311.github.io/RDesk/"><img src="https://github.com/Janakiraman-311/RDesk/actions/workflows/pkgdown.yaml/badge.svg" alt="pkgdown"/></a>
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"/>
  <img src="https://img.shields.io/badge/platform-Windows-informational" alt="Windows only"/>
</p>

<p align="center">
  <strong>Build native Windows desktop apps with R — zero ports, one installer, no R needed by your users.</strong>
</p>

---

**RDesk** turns your R analysis into a standalone Windows application. No Shiny server. No browser tabs. No IT conversations about ports. Your users get a real `.exe` that double-clicks like any other desktop tool — and it works entirely offline.

## Quick Start

```r
# Install from CRAN
install.packages("RDesk")

# Scaffold a professional dashboard
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
# → dist/MyApp-1.0.0-setup.exe  (~200 MB, self-contained)
```

Send the `.exe` to anyone on Windows. They double-click it. Done. No R required.

> **Development version:**
> ```r
> devtools::install_github("Janakiraman-311/RDesk")
> ```

## Why RDesk?

| | Shiny | RInno (archived) | Electron + R | **RDesk** |
|:---|:---:|:---:|:---:|:---:|
| Network ports required | ✅ Yes | ✅ Yes | ✅ Yes | ❌ **Zero** |
| Works fully offline | ❌ No | ⚠️ Partial | ⚠️ Partial | ✅ **Yes** |
| Native file dialogs & menus | ❌ No | ❌ No | ⚠️ Via JS | ✅ **Yes** |
| Distribution format | Server URL | Installer | Installer | **ZIP or .exe** |
| Bundle size | Server-side | 350 MB+ | 350–500 MB | **~200 MB** |
| Skills required | R | R + Electron | R + Node.js | **R only** |

## Core Features

- **🔒 Zero-Port IPC** — R and the UI communicate via native stdin/stdout pipes and Win32 messages. No TCP stack. No firewall rules. Passes enterprise security audits that Shiny deployments fail.
- **⚡ Async by Default** — Three-tier async engine built on `mirai`. Pre-warmed daemon pools start tasks in milliseconds, not seconds. Loading overlays and progress bars are one line of code.
- **📦 Version-Safe Runtime** — `build_app()` copies your exact R installation into the bundle, guaranteeing the runtime and your `renv`-locked packages are always the same version. No more ABI crashes.
- **🎨 Modern Web UI** — Write your interface in plain HTML/CSS/JS. Keep 100% of your logic in R. No React. No Webpack. No build pipeline.
- **🛠 Professional Scaffolding** — `rdesk_create_app()` generates a full working dashboard — sidebar, charts, async workers, dark mode — that runs immediately. No blank-template frustration.
- **🔄 Auto-Update** — One function silently checks for updates on launch and installs them. Your distributed users always run the latest version.

## Who It's For

RDesk is built for R developers who need to put a real tool in the hands of people who don't use R.

- **Pharma & clinical** — distribute data review or validation tools to investigators without IT involvement
- **Consulting** — hand a client a branded analysis tool without exposing your model or code
- **Internal teams** — replace aging Excel macros with proper statistics, distributed as a familiar `.exe`
- **Anyone** who has been told "we can't open a port for your Shiny app"

## Documentation

Full documentation at **[janakiraman-311.github.io/RDesk](https://janakiraman-311.github.io/RDesk/)**

| Guide | What it covers |
|:---|:---|
| [Getting Started](https://janakiraman-311.github.io/RDesk/articles/getting-started.html) | From `install.packages()` to your first native app |
| [Coming from Shiny](https://janakiraman-311.github.io/RDesk/articles/shiny-migration.html) | Side-by-side mapping of every Shiny pattern to RDesk |
| [Async Guide](https://janakiraman-311.github.io/RDesk/articles/async-guide.html) | Background tasks, progress overlays, cancellation |
| [Cookbook](https://janakiraman-311.github.io/RDesk/articles/cookbook.html) | Copy-paste recipes for common desktop patterns |
| [Why RDesk?](https://janakiraman-311.github.io/RDesk/articles/rdesk-article.html) | The history of R desktop deployment |

## License

MIT © Janakiraman G.
