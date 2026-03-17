# RDesk

The first native desktop app framework for R.

## Installation

```r
# Install from source
install.packages("RDesk", repos = NULL, type = "source")
```

## Usage

```r
library(RDesk)

# 1. Create a new modular project
RDesk::rdesk_create_app("MyNewApp")

# 2. Build the standalone bundle
RDesk::build_app("MyNewApp")
```

## Features

- **Project Scaffolding**: Bootstrap professional RDesk apps with a single command.
- **Modular Architecture**: Separate data, plots, and server logic for cleaner scaling.
- **Standardized IPC**: A robust, versioned JSON message contract for R-to-UI communication.
- **Standalone Distribution**: Bundles a portable R runtime and all dependencies.
- **Native OS Integration**: System tray, native menus, and file dialogs.
