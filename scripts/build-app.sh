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

# Ad-hoc signature so Gatekeeper / SSH helpers behave.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1 || \
    echo "    (codesign skipped)"

echo "==> Done: $APP"
echo "    Run with: open \"$APP\""
