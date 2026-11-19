# RDesk Local Development Setup & Workflows

Exact toolchain paths, library locations, and verified commands for developing RDesk on this Windows workstation.

---

## 1. Local Toolchain Paths (Windows)

`Rscript.exe` and `g++.exe` are **not** on the default PowerShell `PATH` in fresh shells. Always prepend them in scripts:

```powershell
$env:PATH = "C:\rtools45\x86_64-w64-mingw32.static.posix\bin;C:\rtools45\usr\bin;C:\Program Files\R\R-4.5.1\bin;" + $env:PATH
```

| Tool | Path |
|---|---|
| R 4.5.1 (`Rscript.exe`) | `C:\Program Files\R\R-4.5.1\bin\Rscript.exe` |
| R 4.5.1 (`R.exe`) | `C:\Program Files\R\R-4.5.1\bin\R.exe` |
| Rtools45 C++ (`g++.exe`, GCC 14.3.0) | `C:\rtools45\x86_64-w64-mingw32.static.posix\bin\g++.exe` |
| Rtools45 Unix utils (`make`, `sh`, `cp`) | `C:\rtools45\usr\bin` |
| Inno Setup 6 (`ISCC.exe`) | `C:\Users\Janak\AppData\Local\Programs\Inno Setup 6\ISCC.exe` |
| `Rapp` CLI launcher (`rdesk.bat`) | `C:\Users\Janak\AppData\Local\Programs\R\Rapp\bin\rdesk.bat` |
| GitHub CLI (`gh`) | **Not installed** — query GitHub API directly via `Invoke-RestMethod` |

---

## 2. Dual R Library Workflow (`renv` vs. Global User Library)

This repo contains `.Rprofile` + `renv/`, which creates **two** R library locations:

1. **Project `renv` library** (used when R starts inside `c:\Users\Janak\OneDrive\Documents\RDesk`):
   `C:\Users\Janak\AppData\Local\R\cache\R\renv\library\RDesk-e8dc2aea\windows\R-4.5\x86_64-w64-mingw32`
2. **Global user library** (used when `Rscript.exe` or `rdesk.bat` starts from `C:\Users\Janak` or any directory outside the repo):
   `C:\Users\Janak\AppData\Local\R\win-library\4.5`

Whenever you install updated `RDesk` locally (so both repo dev mode and global `rdesk` CLI work seamlessly), install to **both** libraries and refresh the `Rapp` launcher:

```powershell
$env:PATH = "C:\rtools45\x86_64-w64-mingw32.static.posix\bin;C:\rtools45\usr\bin;C:\Program Files\R\R-4.5.1\bin;" + $env:PATH
& "C:\Program Files\R\R-4.5.1\bin\R.exe" CMD INSTALL --no-multiarch -l "C:\Users\Janak\AppData\Local\R\win-library\4.5" .
& "C:\Program Files\R\R-4.5.1\bin\R.exe" CMD INSTALL --no-multiarch .
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" -e "RDesk::install_rdesk_cli(overwrite = TRUE)"
```

Ensure `Rapp` is installed in the global library as well (`install.packages("Rapp", lib = "C:/Users/Janak/AppData/Local/R/win-library/4.5")`), otherwise `rdesk` run from outside the repo fails with `there is no package called 'Rapp'`.

---

## 3. Fast C++ Launcher Rebuild (Zero Warnings)

When iterating on `src/launcher.cpp` or `src/webview/webview.h`, compile directly with strict warnings (`-Wall -pedantic`) and sync binary timestamps so `devtools::load_all()` does not trigger redundant rebuilds:

```powershell
$env:PATH = "C:\rtools45\x86_64-w64-mingw32.static.posix\bin;C:\rtools45\usr\bin;" + $env:PATH
Push-Location src
& "C:\rtools45\x86_64-w64-mingw32.static.posix\bin\g++.exe" -std=gnu++17 -O2 -Wall -pedantic `
  -I. -I../inst/include -Iwebview2_sdk/build/native/include -DUNICODE -D_UNICODE `
  launcher.cpp -Lwebview2_sdk/build/native/x64 -lWebView2LoaderStatic `
  -lole32 -lshell32 -lshlwapi -luser32 -lgdi32 -lversion -luuid -lcomdlg32 `
  -o rdesk-launcher.exe -mwindows
Pop-Location
Copy-Item -Force src\rdesk-launcher.exe inst\bin\rdesk-launcher.exe
```

---

## 4. Routine Verification Commands

```powershell
# Document, test, and spell-check
$env:PATH = "C:\rtools45\x86_64-w64-mingw32.static.posix\bin;C:\rtools45\usr\bin;C:\Program Files\R\R-4.5.1\bin;" + $env:PATH
& "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" -e "devtools::document(); devtools::test(); print(spelling::spell_check_package())"

# Check GitHub Actions status (without gh CLI)
$runs = Invoke-RestMethod -Uri "https://api.github.com/repos/Janakiraman-311/RDesk/actions/runs?per_page=10"
$runs.workflow_runs | Select-Object id, name, head_branch, status, conclusion | Format-Table -AutoSize
```

---

## 5. Launching Showcase Apps Locally (External Terminal Only)

Open **Windows Terminal / PowerShell from the Windows Start Menu** (not Antigravity's built-in terminal):

```powershell
rdesk --help
rdesk demo
rdesk demo cars --detach
rdesk demo studio --detach
rdesk demo starter --theme dark --detach
rdesk run path\to\MyApp --debug
```
