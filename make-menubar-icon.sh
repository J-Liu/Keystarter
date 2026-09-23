#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT_DIR/Resources/MenuBar/menubar.svg"
OUT="$ROOT_DIR/Resources/MenuBar"

mkdir -p "$OUT"

for theme in light dark; do
    if [ "$theme" = "light" ]; then
        FILL="#000000"
    else
        FILL="#FFFFFF"
    fi

    TMP="$OUT/menubar-$theme.svg"
    sed "s/__FILL__/$FILL/" "$SRC" > "$TMP"

    rsvg-convert -w 18 -h 18 -o "$OUT/menubar-$theme.png" "$TMP"
    rsvg-convert -w 36 -h 36 -o "$OUT/menubar-$theme@2x.png" "$TMP"

    rm "$TMP"
done

echo "✅ Generated:"
ls -1 "$OUT"/*.png
