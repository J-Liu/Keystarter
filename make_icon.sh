#!/bin/bash
# make_icon.sh
# Compiles Resources/Keystarter.icon into Resources/Compiled/Assets.car.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔧 Compiling icon..."

mkdir -p "$ROOT_DIR/Resources/Compiled"

xcrun actool "$ROOT_DIR/Resources/Keystarter.icon" \
    --compile "$ROOT_DIR/Resources/Compiled" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon Keystarter \
    --output-partial-info-plist /dev/null

echo "✅ Icon compiled: Resources/Compiled/Assets.car"
