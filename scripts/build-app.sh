#!/usr/bin/env bash
# Build Symplast and assemble a launchable .app bundle.
#
# Two distribution shapes are produced from the same build:
#
#   ./scripts/build-app.sh                  # bodyless: mutagen resolved from the system
#   BUNDLE_MUTAGEN=1 ./scripts/build-app.sh # self-contained: mutagen embedded in the app
#
# Optional environment:
#   MUTAGEN_BIN=/path/to/mutagen   source binary to embed (default: auto-detect)
#   MUTAGEN_BIN_ALT=/path/to/other second-arch binary, lipo'd into a universal one
#   MUTAGEN_AGENTS=/path/to/mutagen-agents.tar.gz  agent bundle (default: auto-detect)
#   CODESIGN_IDENTITY="Developer ID Application: …"  signing identity (default: ad-hoc)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="Symplast"
BUNDLE_ID="com.dylanbertram.symplast"
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
ARCH_ARGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_ARGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building $APP_NAME ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}

# Rasterize the logo (white on transparent) from its SVG source when it changes.
# Drop the new mark at logo.svg to regenerate both the menu-bar asset and icon.
SVG="$ROOT/logo.svg"
PNG="$ROOT/Resources/AppLogo.png"
if [[ -f "$SVG" ]] && { [[ ! -f "$PNG" ]] || [[ "$SVG" -nt "$PNG" ]]; }; then
    echo "==> Rendering logo from $(basename "$SVG")"
    swift "$ROOT/scripts/make-logo.swift" "$SVG" "$PNG" 1024 || \
        echo "    (logo render failed; using existing PNG if any)"
fi

BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
APP="$ROOT/build/$APP_NAME.app"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -n "${APP_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$APP/Contents/Info.plist"
fi
cp "$ROOT/LICENSE" "$ROOT/THIRD-PARTY-NOTICES.md" "$APP/Contents/Resources/"
if [[ -f "$PNG" ]]; then
    cp "$PNG" "$APP/Contents/Resources/AppLogo.png"
fi

# Build the app icon (.icns) from the mark.
ICON_PNG="$ROOT/Resources/AppIcon-1024.png"
if [[ -f "$PNG" ]] && { [[ ! -f "$ICON_PNG" ]] || [[ "$PNG" -nt "$ICON_PNG" ]]; }; then
    swift "$ROOT/scripts/make-icon.swift" "$PNG" "$ICON_PNG" 1024 || \
        echo "    (icon render failed; using existing icon if any)"
fi
if [[ -f "$ICON_PNG" ]]; then
    ICON_WORK="$(mktemp -d "${TMPDIR:-/tmp}/symplast-icon.XXXXXX")"
    trap 'rm -rf "$ICON_WORK"' EXIT
    ICONSET="$ICON_WORK/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
                "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
                "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
        set -- $spec
        sips -z "$1" "$1" "$ICON_PNG" --out "$ICONSET/$2.png" >/dev/null 2>&1
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    echo "    app icon: AppIcon.icns"
fi

# Locate a mutagen binary to embed, in order: MUTAGEN_BIN, PATH, the Homebrew
# tap, then the usual install locations.
find_mutagen_bin() {
    local candidates=()
    if [[ -n "${MUTAGEN_BIN:-}" ]]; then candidates+=("$MUTAGEN_BIN"); fi
    if command -v mutagen >/dev/null 2>&1; then candidates+=("$(command -v mutagen)"); fi
    if command -v brew >/dev/null 2>&1; then
        local prefix
        prefix="$(brew --prefix mutagen 2>/dev/null || true)"
        [[ -n "$prefix" ]] && candidates+=("$prefix/bin/mutagen")
    fi
    candidates+=("/opt/homebrew/bin/mutagen" "/usr/local/bin/mutagen")
    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi
    done
    return 1
}

# Locate the agent bundle that mutagen expects next to its executable (or in a
# sibling libexec directory). Without it, remote (SSH/Docker) sync cannot push
# an agent to the endpoint.
find_agents_bundle() {
    local candidates=()
    if [[ -n "${MUTAGEN_AGENTS:-}" ]]; then candidates+=("$MUTAGEN_AGENTS"); fi
    if [[ -n "${SRC:-}" ]]; then
        candidates+=("$(dirname "$SRC")/mutagen-agents.tar.gz")
        candidates+=("$(dirname "$SRC")/../libexec/mutagen-agents.tar.gz")
    fi
    if command -v brew >/dev/null 2>&1; then
        local prefix
        prefix="$(brew --prefix mutagen 2>/dev/null || true)"
        [[ -n "$prefix" ]] && candidates+=("$prefix/libexec/mutagen-agents.tar.gz")
    fi
    candidates+=("/opt/homebrew/opt/mutagen/libexec/mutagen-agents.tar.gz"
                 "/usr/local/opt/mutagen/libexec/mutagen-agents.tar.gz")
    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi
    done
    return 1
}

if [[ "${BUNDLE_MUTAGEN:-0}" == "1" ]]; then
    if ! SRC="$(find_mutagen_bin)"; then
        echo "error: BUNDLE_MUTAGEN=1 but no mutagen binary was found." >&2
        echo "       Install mutagen or point MUTAGEN_BIN at one." >&2
        exit 1
    fi
    DEST="$APP/Contents/Resources/mutagen"
    echo "==> Embedding mutagen from $SRC"
    if [[ -n "${MUTAGEN_BIN_ALT:-}" ]]; then
        [[ -x "$MUTAGEN_BIN_ALT" ]] || { echo "error: MUTAGEN_BIN_ALT is not executable: $MUTAGEN_BIN_ALT" >&2; exit 1; }
        lipo -create "$SRC" "$MUTAGEN_BIN_ALT" -output "$DEST"
    else
        cp "$SRC" "$DEST"
    fi
    chmod 755 "$DEST"
    echo "    architectures: $(lipo -archs "$DEST" 2>/dev/null || echo unknown)"

    if AGENTS_SRC="$(find_agents_bundle)"; then
        cp "$AGENTS_SRC" "$APP/Contents/Resources/mutagen-agents.tar.gz"
        echo "    agents bundle: $(du -h "$AGENTS_SRC" | cut -f1)"
    else
        echo "error: bundled builds require MUTAGEN_AGENTS; remote sync would otherwise fail." >&2
        exit 1
    fi
    if [[ -d "$ROOT/build/mutagen/licenses" ]]; then
        cp -R "$ROOT/build/mutagen/licenses" "$APP/Contents/Resources/Mutagen-Licenses"
    fi
fi

# Sign nested executables first, then the app. `--deep` is not sufficient for
# notarization, so the embedded binary is signed explicitly. A real identity
# gets the hardened runtime and a secure timestamp, which notarization needs.
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_ARGS+=(--options runtime --timestamp)
fi
if [[ -f "$APP/Contents/Resources/mutagen" ]]; then
    codesign "${SIGN_ARGS[@]}" "$APP/Contents/Resources/mutagen"
fi
codesign "${SIGN_ARGS[@]}" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict "$APP"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    for arch in arm64 x86_64; do
        lipo "$APP/Contents/MacOS/$APP_NAME" -verify_arch "$arch"
        if [[ -f "$APP/Contents/Resources/mutagen" ]]; then
            lipo "$APP/Contents/Resources/mutagen" -verify_arch "$arch"
        fi
    done
fi

echo "==> Done: $APP"
echo "    Run with: open \"$APP\""
