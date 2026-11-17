#!/usr/bin/env Rapp
#| name: rdesk
#| title: RDesk Command-Line Interface
#| description: Create, build, and inspect standalone RDesk desktop applications.

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

    #| description: Also build a platform installer (.exe via Inno Setup on Windows).
    #| short: i
    installer <- FALSE

    #| description: Installer scope on Windows ("user" or "system").
    #| short: s
    install_scope <- "user"

    #| description: Overwrite existing output artifacts.
    overwrite <- FALSE

    #| description: Prune unnecessary docs and tests from the bundled runtime.
    prune_runtime <- TRUE

    #| description: Validate structure and environment without building.
    dry_run <- FALSE

    RDesk::build_app(
      app_dir         = app_dir,
      out_dir         = out_dir,
      app_name        = if (is.na(app_name)) NULL else app_name,
      version         = if (is.na(version)) NULL else version,
      overwrite       = overwrite,
      build_installer = installer,
      install_scope   = install_scope,
      prune_runtime   = prune_runtime,
      dry_run         = dry_run
    )
  },

  #| title: Report RDesk toolchain and runtime readiness
  sitrep = {
    RDesk::rdesk_sitrep()
  }
)
