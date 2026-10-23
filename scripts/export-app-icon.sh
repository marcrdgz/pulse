#!/usr/bin/env bash
# Rasterises design/app-icon.svg into every PNG of the AppIcon asset catalog.
# Usage: scripts/export-app-icon.sh [path/to/icon.svg]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
svg="${1:-$root/design/app-icon.svg}"
iconset="$root/Pulse/Resources/Assets.xcassets/AppIcon.appiconset"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

# The SVG is a full-bleed tile. macOS (Big Sur+) icons draw the tile at
# 824/1024 of the canvas, centred on transparency, to line up in the Dock.
canvas=1024
tile=824

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/icon.html" <<EOF
<!doctype html>
<style>
  html, body { margin: 0; background: transparent; }
  img { display: block; width: ${tile}px; height: ${tile}px; margin: $(((canvas - tile) / 2))px; }
</style>
<img src="file://$svg">
EOF

"$chrome" --headless --disable-gpu --hide-scrollbars --allow-file-access-from-files \
  --default-background-color=00000000 --force-device-scale-factor=1 \
  --window-size="$canvas,$canvas" --screenshot="$work/icon_1024.png" \
  "file://$work/icon.html" >/dev/null 2>&1

render() { # <pixels> <filename>
  sips -z "$1" "$1" "$work/icon_1024.png" --out "$iconset/$2" >/dev/null
}

for size in 16 32 128 256 512; do
  render "$size" "icon_${size}.png"
  render "$((size * 2))" "icon_${size}@2x.png"
done

echo "Exported AppIcon from $svg"
