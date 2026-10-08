#!/usr/bin/env bash
# Build Symplast, install it to /Applications, and launch it.
#
# Pass BUNDLE_MUTAGEN=1 to embed mutagen and produce a self-contained install:
#   BUNDLE_MUTAGEN=1 ./scripts/install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Symplast"
DEST="/Applications/$APP_NAME.app"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$ROOT/scripts/build-app.sh"

echo "==> Installing to $DEST"
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$DEST"
cp -R "$ROOT/build/$APP_NAME.app" "$DEST"

# Remove the build copy so LaunchServices doesn't register a second app with
# the same bundle identifier (which shows up as a duplicate in Launchpad).
"$LSREGISTER" -u "$ROOT/build/$APP_NAME.app" >/dev/null 2>&1 || true
rm -rf "$ROOT/build/$APP_NAME.app"

# Re-register the installed app so Spotlight/Finder pick up the icon.
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true
touch "$DEST"

echo "==> Launching"
# `open` only activates an existing instance, so quit any running copy first.
sleep 1
open "$DEST"
