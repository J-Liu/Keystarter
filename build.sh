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

# 3. Ad-hoc sign (required on Apple Silicon)
echo "==> Signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "==> Done: ${APP_BUNDLE}"
echo "    Run:  open \"${APP_BUNDLE}\""
