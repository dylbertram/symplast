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

# Remove the build copy so LaunchServices doesn't register a second app with
# the same bundle identifier (which shows up as a duplicate in Launchpad).
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$ROOT/build/$APP_NAME.app" >/dev/null 2>&1 || true
rm -rf "$ROOT/build/$APP_NAME.app"

# Re-register the installed app so Spotlight/Finder pick up the icon.
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
touch "$DEST"

echo "==> Launching"
open "$DEST"
