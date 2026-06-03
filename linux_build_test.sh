#!/usr/bin/env bash
# ============================================================================
# RDesk Linux Build & Test Script (WSL Ubuntu)
# ============================================================================
# Run this INSIDE your WSL terminal (not PowerShell):
#   wsl
#   bash /mnt/c/Users/Janak/OneDrive/Documents/RDesk/linux_build_test.sh
# ============================================================================

set -e  # Exit on first error

WINDOWS_SRC="/mnt/c/Users/Janak/OneDrive/Documents/RDesk"
LINUX_BUILD="$HOME/RDesk-linux-build"
TARBALL_DIR="$HOME/RDesk-dist"

echo ""
echo "=============================================="
echo " RDesk Linux Build & Test Script"
echo "=============================================="
echo ""

# ── Step 1: Verify System Dependencies ───────────────────────────────────────
echo "[1/6] Checking system dependencies..."

missing_deps=()

if ! pkg-config --exists gtk+-3.0 2>/dev/null; then
    missing_deps+=("libgtk-3-dev")
fi

if ! pkg-config --exists webkit2gtk-4.1 2>/dev/null && ! pkg-config --exists webkit2gtk-4.0 2>/dev/null; then
    missing_deps+=("libwebkit2gtk-4.1-dev")
fi

if [ ${#missing_deps[@]} -gt 0 ]; then
    echo "  Installing missing system packages: ${missing_deps[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y "${missing_deps[@]}"
else
    WEBKIT_VER=$(pkg-config --modversion webkit2gtk-4.1 2>/dev/null || pkg-config --modversion webkit2gtk-4.0 2>/dev/null)
    GTK_VER=$(pkg-config --modversion gtk+-3.0 2>/dev/null)
    echo "  OK GTK+3: $GTK_VER"
    echo "  OK WebKit2GTK: $WEBKIT_VER"
fi

echo ""

# ── Step 2: Verify R and required packages ────────────────────────────────────
echo "[2/6] Checking R and required packages..."
R_VER=$(R --vanilla --quiet -e "cat(R.version.string)" 2>/dev/null | grep -v "^>" | tr -d '\n')
echo "  OK $R_VER"

Rscript --vanilla -e "
pkgs <- c('R6','jsonlite','digest','processx','callr','mirai','base64enc','zip','testthat','withr')
installed <- rownames(installed.packages())
missing <- setdiff(pkgs, installed)
if (length(missing) > 0) {
  cat('  Installing missing R packages:', paste(missing, collapse=', '), '\n')
  install.packages(missing, repos='https://packagemanager.posit.co/cran/latest', quiet=TRUE)
} else {
  cat('  OK All required R packages are installed\n')
}
"

echo ""

# ── Step 3: Copy source to WSL native filesystem ─────────────────────────────
echo "[3/6] Copying source to WSL native filesystem..."
rm -rf "$LINUX_BUILD"
mkdir -p "$LINUX_BUILD"

rsync -a \
    --exclude='.git/' \
    --exclude='renv/library/' \
    --exclude='src/*.o' \
    --exclude='src/*.so' \
    --exclude='src/*.dll' \
    --exclude='src/*.exe' \
    --exclude='inst/bin/*.exe' \
    --exclude='src/RDesk.so' \
    --exclude='src/RDesk.dll' \
    "$WINDOWS_SRC/" "$LINUX_BUILD/"

echo "  OK Source copied to: $LINUX_BUILD"
echo ""

# ── Step 4: Build source tarball ─────────────────────────────────────────────
echo "[4/6] Building source package tarball..."
mkdir -p "$TARBALL_DIR"
cd "$HOME"

RENV_CONFIG_AUTOLOADER_ENABLED=false \
    R CMD build "$LINUX_BUILD" \
    --no-build-vignettes \
    --no-manual \
    2>&1

TARBALL=$(ls -t ~/RDesk_*.tar.gz 2>/dev/null | head -1)
if [ -z "$TARBALL" ]; then
    echo "  ERROR: Tarball not found after build!"
    exit 1
fi

mv "$TARBALL" "$TARBALL_DIR/"
TARBALL="$TARBALL_DIR/$(basename "$TARBALL")"
echo "  OK Tarball built: $TARBALL"
echo ""

# ── Step 5: R CMD check ───────────────────────────────────────────────────────
echo "[5/6] Running R CMD check..."
echo "  (Suggested packages like knitr/devtools are not required to pass check)"

_R_CHECK_FORCE_SUGGESTS_=false \
_R_CHECK_CRAN_INCOMING_REMOTE_=false \
_R_CHECK_CRAN_INCOMING_=false \
RENV_CONFIG_AUTOLOADER_ENABLED=false \
    R CMD check "$TARBALL" \
    --no-manual \
    --no-build-vignettes \
    --ignore-vignettes \
    --as-cran \
    2>&1

echo "  OK R CMD check completed"
echo ""


# ── Step 6: Install package ──────────────────────────────────────────────────
echo "[6/6] Installing RDesk into R library..."

RENV_CONFIG_AUTOLOADER_ENABLED=false \
    R CMD INSTALL "$TARBALL" 2>&1

echo ""
echo "=============================================="
echo " Linux Build Complete!"
echo "=============================================="
echo ""
echo " Tarball: $TARBALL"
echo ""
echo " Verify install:"
echo "   Rscript --vanilla -e \"library(RDesk); packageVersion('RDesk')\""
echo ""
echo " Run unit tests:"
echo "   cd $LINUX_BUILD && RENV_CONFIG_AUTOLOADER_ENABLED=false Rscript --vanilla -e \"devtools::test()\""
echo ""
echo " Launch demo app (requires WSLg or X11 display):"
echo "   Rscript --vanilla -e \"library(RDesk); app <- App\$new('Hello Linux', 1200, 800); app\$run()\""
echo ""
