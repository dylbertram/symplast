#!/usr/bin/env bash
# Build MutagenDock, install it to /Applications, and launch it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MutagenDock"
DEST="/Applications/$APP_NAME.app"

"$ROOT/scripts/build-app.sh"

echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -R "$ROOT/build/$APP_NAME.app" "$DEST"

echo "==> Launching"
open "$DEST"
