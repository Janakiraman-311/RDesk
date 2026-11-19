# RDesk — AI Agent Guide

**RDesk** packages R analyses into standalone native desktop
applications using an embedded system webview (**WebView2** on Windows,
**WKWebView** on macOS, **WebKitGTK** on Linux) and **stdin/stdout JSON
IPC** — with **zero HTTP servers and zero open network ports**.

Read the structured documentation in `.agents/` before making changes:

| File | Purpose |
|----|----|
| [.agents/rules.md](https://janakiraman-311.github.io/RDesk/.agents/rules.md) | Branch isolation (`main` vs. `dev`), architecture invariants, and mandatory pre-push gates |
| [.agents/setup.md](https://janakiraman-311.github.io/RDesk/.agents/setup.md) | Local Windows toolchain paths, dual `renv`/global library workflow, C++ build, and `rdesk` CLI usage |
| [.agents/decisions.md](https://janakiraman-311.github.io/RDesk/.agents/decisions.md) | Architecture Decision Records (ADRs) explaining *why* RDesk is designed this way |
| [.agents/gotchas.md](https://janakiraman-311.github.io/RDesk/.agents/gotchas.md) | Known pitfalls, platform traps, CI quirks, and proven fixes |
| [.agents/cran-submission.md](https://janakiraman-311.github.io/RDesk/.agents/cran-submission.md) | CRAN preflight checklist (`rcmdcheck`, `spelling`, `urlchecker`, `_pkgdown.yml`, `.Rbuildignore`) |

## Non-Negotiable Quick Rules

1.  **Strict Branch Separation**:
    - `main` and `release/v1.0.7-windows` are strictly for the **Windows
      CRAN package** (`OS_type: windows`, no Unix `configure` /
      `src/Makevars`).
    - `dev` is the **cross-platform branch** (Windows + macOS + Linux).
      Never merge `dev` into `main` until cross-platform CRAN readiness
      is explicitly approved.
2.  **Zero-Port Architecture**: Never introduce `httpuv`, `plumber`,
    `WebSocket`, or localhost TCP listeners. UI assets are served via
    virtual host (`https://app.rdesk/` on Windows) or custom URI scheme
    (`rdesk://app/` on macOS/Linux), and R $`\leftrightarrow`$ JS
    messaging flows strictly over stdin/stdout pipes.
3.  **Keep CRAN Tarball Clean**: Any repo-level docs or agent files
    (including `AGENTS.md` and `.agents/`) must be excluded in
    `.Rbuildignore`.
4.  **Verify Before Pushing**: Run `devtools::document()`,
    `devtools::test()`, and `spelling::spell_check_package()` locally,
    and confirm `_pkgdown.yml` indexes every exported function.
5.  **External Terminal for Local GUI Launches**: Antigravity’s built-in
    terminal and agent `run_command` execute on a hidden sandbox Windows
    desktop (`exebox-...`). Launch GUI apps from an external Windows
    Terminal / PowerShell / RStudio session to view windows on the
    monitor.
