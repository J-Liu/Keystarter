#!/bin/bash
# build.sh
# Builds the Keystarter Swift package and packages it into a proper .app bundle.
# Usage: ./build.sh

set -euo pipefail

APP_NAME="Keystarter"
BUILD_CONFIG="release"

# Resolve project root (script is in root)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# 1. Build the binary
echo "==> Building ${APP_NAME} (${BUILD_CONFIG})..."
swift build -c "$BUILD_CONFIG"

BINARY_PATH="$(swift build -c "$BUILD_CONFIG" --show-bin-path)/${APP_NAME}"
if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: binary not found at ${BINARY_PATH}"
    exit 1
fi

# 2. Assemble .app bundle structure (in root directory)
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
echo "==> Assembling ${APP_BUNDLE}..."

rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "$BINARY_PATH" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy Info.plist from Resources/
cp "${ROOT_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Copy pre-compiled icon assets (committed to git)
ICON_DIR="${ROOT_DIR}/Resources/Compiled"
if [ -f "${ICON_DIR}/Assets.car" ]; then
    cp "${ICON_DIR}/Assets.car" "${APP_BUNDLE}/Contents/Resources/Assets.car"
fi
if [ -f "${ICON_DIR}/${APP_NAME}.icns" ]; then
    cp "${ICON_DIR}/${APP_NAME}.icns" "${APP_BUNDLE}/Contents/Resources/${APP_NAME}.icns"
fi

# Copy menu bar icons
if [ -d "${ROOT_DIR}/Resources/MenuBar" ]; then
    cp "${ROOT_DIR}/Resources/MenuBar/"*.png "${APP_BUNDLE}/Contents/Resources/"
fi

# Copy Info.plist
cp "${ROOT_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
# Set LSUIElement to true (hide from Dock by default)
/usr/libexec/PlistBuddy -c "Set :LSUIElement true" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || true

# 3. Ad-hoc sign (required on Apple Silicon)
echo "==> Signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "==> Done: ${APP_BUNDLE}"
echo "    Run:  open \"${APP_BUNDLE}\""
