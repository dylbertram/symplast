#!/usr/bin/env bash
# Build MutagenDock and assemble a launchable .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="MutagenDock"
BUNDLE_ID="com.dylanbertram.mutagendock"

echo "==> Building $APP_NAME ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"

# Rasterize the logo (white on transparent) from its SVG source when it changes.
SVG="$ROOT/logo_light.svg"
PNG="$ROOT/Resources/MutagenLogo.png"
if [[ -f "$SVG" ]] && { [[ ! -f "$PNG" ]] || [[ "$SVG" -nt "$PNG" ]]; }; then
    echo "==> Rendering logo from $(basename "$SVG")"
    swift "$ROOT/scripts/make-logo.swift" "$SVG" "$PNG" 1024 || \
        echo "    (logo render failed; using existing PNG if any)"
fi

BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
APP="$ROOT/build/$APP_NAME.app"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/MutagenLogo.png" ]]; then
    cp "$ROOT/Resources/MutagenLogo.png" "$APP/Contents/Resources/MutagenLogo.png"
fi

# Build the app icon (.icns) from the mark.
ICON_PNG="$ROOT/Resources/AppIcon-1024.png"
if [[ -f "$ROOT/Resources/MutagenLogo.png" ]] && { [[ ! -f "$ICON_PNG" ]] || [[ "$ROOT/Resources/MutagenLogo.png" -nt "$ICON_PNG" ]]; }; then
    swift "$ROOT/scripts/make-icon.swift" "$ROOT/Resources/MutagenLogo.png" "$ICON_PNG" 1024 || \
        echo "    (icon render failed; using existing icon if any)"
fi
if [[ -f "$ICON_PNG" ]]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
                "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
                "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
        set -- $spec
        sips -z "$1" "$1" "$ICON_PNG" --out "$ICONSET/$2.png" >/dev/null 2>&1
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 && \
        echo "    app icon: AppIcon.icns" || echo "    (iconutil failed; no app icon)"
fi

# Ad-hoc signature so Gatekeeper / SSH helpers behave.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1 || \
    echo "    (codesign skipped)"

echo "==> Done: $APP"
echo "    Run with: open \"$APP\""
