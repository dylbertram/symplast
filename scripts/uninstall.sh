#!/usr/bin/env bash
# Remove a locally installed Symplast — the counterpart to scripts/install.sh.
#
#   ./scripts/uninstall.sh           quit Symplast and remove it from /Applications
#   ./scripts/uninstall.sh --purge   also remove preferences and saved sessions
#
# Like the documented uninstall, this never touches Mutagen: the daemon, its
# sessions and your files stay exactly as they are.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Symplast"
BUNDLE_ID="com.dylanbertram.symplast"
DEST="/Applications/$APP_NAME.app"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

usage() {
    echo "Usage: $0 [--purge]"
    echo "  --purge   also remove preferences and saved session definitions"
}

PURGE=0
for argument in "$@"; do
    case "$argument" in
        --purge|--zap) PURGE=1 ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $argument" >&2
            usage >&2
            exit 2
            ;;
    esac
done

echo "==> Quitting $APP_NAME if it is running"
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
# Give it a moment to exit so its bundle can be removed.
sleep 1

removed=0
for candidate in "$DEST" "$ROOT/build/$APP_NAME.app"; do
    if [ -d "$candidate" ]; then
        echo "==> Removing $candidate"
        rm -rf "$candidate"
        removed=1
    fi
    # Clear stale LaunchServices records so Spotlight and Launchpad forget it.
    "$LSREGISTER" -u "$candidate" >/dev/null 2>&1 || true
done

if [ "$removed" -eq 0 ]; then
    echo "==> No app found in /Applications or build/ — nothing to remove"
fi

if [ "$PURGE" -eq 1 ]; then
    echo "==> Removing preferences and saved session definitions"
    rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist" \
          "$HOME/Library/Preferences/$BUNDLE_ID.plist.lockfile"
    rm -rf "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" \
           "$HOME/Library/Caches/$BUNDLE_ID" \
           "$HOME/Library/HTTPStorages/$BUNDLE_ID"
else
    echo "==> Preferences and saved sessions kept (pass --purge to remove them)"
fi

echo "==> Done. Mutagen's daemon, sessions and files were not touched."
