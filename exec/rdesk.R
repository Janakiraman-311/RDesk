#!/usr/bin/env Rapp
#| name: rdesk
#| title: RDesk Command-Line Interface
#| description: Create, run, demo, build, and inspect standalone RDesk desktop applications.

switch(
  command <- "",

  #| title: Scaffold a new RDesk application
  new = {
    #| description: Name of the application to create.
    name <- NULL

    #| description: Parent directory where the application folder will be created.
    #| short: p
    path <- "."

    #| description: Theme ("light", "dark", or "system").
    #| short: t
    theme <- "light"

    RDesk::rdesk_create_app(name = name, path = path, theme = theme, open = FALSE)
  },

  #| title: Launch an RDesk desktop application
  run = {
    #| description: Path to an RDesk application directory or app.R file (defaults to ".").
    #| required: false
    path <- NULL

    #| description: Enable RDESK_DEBUG=1 (DevTools and verbose IPC logging).
    #| short: D
    debug <- FALSE

    #| description: Launch in the background and return to the shell immediately.
    #| short: b
    detach <- FALSE

    RDesk::rdesk_run(
      app_dir = if (is.null(path) || !nzchar(path)) "." else path,
      debug   = debug,
      detach  = detach
    )
  },

  #| title: Launch or list built-in RDesk showcase demos
  demo = {
    #| description: Demo name ("cars", "studio", or "starter"). Omit to list demos.
    #| required: false
    name <- NULL

    #| description: Theme for the "starter" demo ("light", "dark", or "system").
    #| short: t
    theme <- "dark"

    #| description: Enable RDESK_DEBUG=1 (DevTools and verbose IPC logging).
    #| short: D
    debug <- FALSE

    #| description: Launch in the background and return to the shell immediately.
    #| short: b
    detach <- FALSE

    RDesk::rdesk_demo(
      name   = name,
      theme  = theme,
      debug  = debug,
      detach = detach
    )
  },

  #| title: Build a standalone RDesk desktop bundle
  build = {
    #| description: Path to the application directory containing app.R and www/.
    #| short: d
    app_dir <- "."

    #| description: Output directory for built artifacts.
    #| short: o
    out_dir <- "dist"

    #| description: Application name (defaults to Package/AppName in DESCRIPTION).
    #| short: n
    app_name <- NA_character_

    #| description: Application version (defaults to Version in DESCRIPTION).
    #| short: v
    version <- NA_character_

    #| description: Path to application icon (.ico on Windows).
    #| short: I
    icon <- NA_character_

    #| description: Publisher name for installer metadata.
    publisher <- NA_character_

    #| description: Publisher or application website URL.
    website <- NA_character_

    #| description: Path to license text file (.txt or .rtf) for installer.
    license <- NA_character_

    #| description: Also build a platform installer (.exe via Inno Setup on Windows).
    #| short: i
    installer <- FALSE

    #| description: Installer scope on Windows ("user" or "system").
    #| short: s
    install_scope <- NA_character_

    #| description: Overwrite existing output artifacts.
    overwrite <- FALSE

    #| description: Prune unnecessary docs and tests from the bundled runtime.
    prune_runtime <- TRUE

    #| description: Reuse cached R runtime and package library across builds.
    cache <- TRUE

    #| description: Validate structure and environment without building.
    dry_run <- FALSE

    RDesk::build_app(
      app_dir         = app_dir,
      out_dir         = out_dir,
      app_name        = if (is.na(app_name)) NULL else app_name,
      version         = if (is.na(version)) NULL else version,
      overwrite       = overwrite,
      build_installer = installer,
      install_scope   = if (is.na(install_scope)) NULL else install_scope,
      publisher       = if (is.na(publisher)) NULL else publisher,
      website         = if (is.na(website)) NULL else website,
      license_file    = if (is.na(license)) NULL else license,
      icon_file       = if (is.na(icon)) NULL else icon,
      prune_runtime   = prune_runtime,
      dry_run         = dry_run,
      use_cache       = isTRUE(cache)
    )
  },

  #| title: Report RDesk toolchain and runtime readiness
  sitrep = {
    RDesk::rdesk_sitrep()
  }
)
