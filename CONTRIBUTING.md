# Contributing to RDesk

Thank you for your interest in RDesk.

## Development setup

1.  Clone the repository
2.  Install Rtools44 from
    <https://cran.r-project.org/bin/windows/Rtools/>
3.  Install dependencies: `devtools::install_deps()`
4.  Run checks: `devtools::check()`

## Important: OneDrive / synced folder warning

Do not develop RDesk from a folder synced by OneDrive or similar. The
g++ compiler reads stale cached source files from synced folders,
producing ghost bugs where code changes have no effect. Always work from
a local non-synced directory such as C:/Projects/RDesk. The build system
copies source to a temp directory to mitigate this, but working locally
is still strongly recommended.

## Building the launcher

The C++ launcher is compiled automatically by build_app(). To compile
manually for development:

``` r
source("R/build.R")
rdesk_build_stub(
  stub_cpp = "inst/stub/stub.cpp",
  out_exe  = "inst/bin/rdesk-launcher.exe",
  app_name = "RDesk"
)
```

## Running the demo app

``` r
devtools::load_all()
source("inst/apps/mtcars_dashboard/app.R")
```

## IPC contract

All messages between R and JavaScript use the standard envelope:
`{id, type, version, payload, timestamp}`. See
`vignettes/ipc-contract.Rmd` for the full specification. Never break
this contract without bumping the version in zzz.R.

## Pull requests

- One feature or fix per PR
- All R code must pass `devtools::check()` with zero warnings
- C++ changes must compile cleanly with Rtools44 g++
- Update NEWS.md with your change
- Update relevant vignettes if the public API changes
