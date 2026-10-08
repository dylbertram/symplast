#!/usr/bin/env bash
# Build both distribution shapes, sign them, and package DMGs into dist/.
#
#   dist/Symplast-<version>.dmg          bodyless (mutagen resolved from the system)
#   dist/Symplast-<version>-bundled.dmg  self-contained (mutagen embedded)
#
# Signing/notarization is opt-in via environment:
#   CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#   APPLE_ID=you@example.com  APPLE_TEAM_ID=TEAMID  APPLE_APP_PASSWORD=app-specific-pw
# Without CODESIGN_IDENTITY local testing builds are ad-hoc signed. A real
# identity requires complete notarization credentials; it never falls back.
#
# The bundled variant needs a mutagen binary and agent bundle; fetch them first
# with scripts/fetch-mutagen.sh. Release packaging only accepts that verified build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
STAGE="$ROOT/build/variants"
TEMP_ROOT="${TMPDIR:-/tmp}/opencode"
mkdir -p "$TEMP_ROOT"
WORK="$(mktemp -d "$TEMP_ROOT/symplast-release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

VERSION="${VERSION:-}"
if [[ -z "$VERSION" && -n "${GITHUB_REF_NAME:-}" ]]; then VERSION="${GITHUB_REF_NAME#v}"; fi
if [[ -z "$VERSION" ]]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
fi
echo "==> Packaging Symplast $VERSION"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: VERSION must be x.y.z" >&2; exit 1; }
export APP_VERSION="$VERSION"
export UNIVERSAL=1
NOTARIZED=0

if [[ -n "${CODESIGN_IDENTITY:-}" && "$CODESIGN_IDENTITY" != "-" ]]; then
    echo "    signing identity: $CODESIGN_IDENTITY"
    : "${APPLE_ID:?Notarized releases require APPLE_ID}"
    : "${APPLE_TEAM_ID:?Notarized releases require APPLE_TEAM_ID}"
    : "${APPLE_APP_PASSWORD:?Notarized releases require APPLE_APP_PASSWORD}"
    NOTARIZED=1
else
    echo "    signing identity: ad-hoc (set CODESIGN_IDENTITY for distribution)"
fi

[[ -f "$ROOT/build/mutagen/licenses/Mutagen-SOURCE.txt" ]] || {
    echo "error: build non-SSPL Mutagen and its legal/source notices before packaging." >&2
    exit 1
}
export MUTAGEN_BIN="${MUTAGEN_BIN:-$ROOT/build/mutagen/mutagen}"
export MUTAGEN_AGENTS="${MUTAGEN_AGENTS:-$ROOT/build/mutagen/mutagen-agents.tar.gz}"
[[ "$MUTAGEN_BIN" == "$ROOT/build/mutagen/mutagen" && "$MUTAGEN_AGENTS" == "$ROOT/build/mutagen/mutagen-agents.tar.gz" ]] || {
    echo "error: release packaging requires the pinned source build; use build-app.sh for custom local binaries" >&2
    exit 1
}
VERIFY_ARGS=()
if [[ "$NOTARIZED" == "1" ]]; then VERIFY_ARGS+=(--signed); fi
python3 "$ROOT/scripts/verify-mutagen.py" "$ROOT/build/mutagen" ${VERIFY_ARGS[@]+"${VERIFY_ARGS[@]}"}
rm -rf "$DIST" "$STAGE"
mkdir -p "$DIST" "$STAGE"

# --- Bodyless ---------------------------------------------------------------
echo "==> Building bodyless variant"
BUNDLE_MUTAGEN=0 bash "$ROOT/scripts/build-app.sh"
mv "$ROOT/build/Symplast.app" "$STAGE/Symplast.app"

# --- Self-contained ---------------------------------------------------------
echo "==> Building self-contained variant"
export BUNDLE_MUTAGEN=1
if [[ -z "${MUTAGEN_BIN:-}" && -x "$ROOT/build/mutagen/mutagen" ]]; then
    export MUTAGEN_BIN="$ROOT/build/mutagen/mutagen"
fi
if [[ -z "${MUTAGEN_AGENTS:-}" && -f "$ROOT/build/mutagen/mutagen-agents.tar.gz" ]]; then
    export MUTAGEN_AGENTS="$ROOT/build/mutagen/mutagen-agents.tar.gz"
fi
bash "$ROOT/scripts/build-app.sh"
mv "$ROOT/build/Symplast.app" "$STAGE/Symplast-bundled.app"

# --- Notarization -----------------------------------------------------------
notarize() {
    local file="$1"
    if [[ -n "${CODESIGN_IDENTITY:-}" && "$CODESIGN_IDENTITY" != "-" ]]; then
        :
    else
        echo "    notarization skipped (no Developer ID identity)"
        return 0
    fi
    echo "    notarizing $(basename "$file")"
    xcrun notarytool submit "$file" \
        --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" --wait
    xcrun stapler staple "$file"
    xcrun stapler validate "$file"
}

# Staple each app before packaging it, so the app remains verifiable offline
# after it is copied out of the disk image.
if [[ "$NOTARIZED" == "1" ]]; then
    for app in "$STAGE/Symplast.app" "$STAGE/Symplast-bundled.app"; do
        zip="$WORK/$(basename "$app").zip"
        ditto -c -k --keepParent "$app" "$zip"
        xcrun notarytool submit "$zip" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_PASSWORD" --wait
        xcrun stapler staple "$app"
        xcrun stapler validate "$app"
        spctl --assess --type execute "$app"
    done
fi

# --- DMGs -------------------------------------------------------------------
make_dmg() {
    local app="$1" out="$2" volname="$3"
    local stage="$WORK/dmg"
    rm -rf "$stage"
    mkdir -p "$stage"
    cp -R "$app" "$stage/Symplast.app"
    ln -s /Applications "$stage/Applications"
    cp "$ROOT/LICENSE" "$ROOT/THIRD-PARTY-NOTICES.md" "$stage/"
    cp "$ROOT/docs/installation.md" "$stage/Installation.txt"
    rm -f "$out"
    hdiutil create -volname "$volname" -srcfolder "$stage" -ov -format UDZO "$out" >/dev/null
    if [[ "$NOTARIZED" == "1" ]]; then
        codesign --sign "$CODESIGN_IDENTITY" --timestamp "$out"
    fi
    notarize "$out"
    echo "    wrote $(basename "$out") ($(du -h "$out" | cut -f1))"
}

echo "==> Creating disk images"
make_dmg "$STAGE/Symplast.app" "$DIST/Symplast-$VERSION.dmg" "Symplast $VERSION"
make_dmg "$STAGE/Symplast-bundled.app" "$DIST/Symplast-$VERSION-bundled.dmg" "Symplast $VERSION"

(cd "$DIST" && shasum -a 256 ./*.dmg > SHA256SUMS)
CASK_ARGS=()
if [[ "$NOTARIZED" == "1" ]]; then CASK_ARGS+=(--notarized); fi
python3 "$ROOT/scripts/generate-cask.py" "$VERSION" "$DIST/Symplast-$VERSION-bundled.dmg" \
    --output "$DIST/symplast.rb" ${CASK_ARGS[@]+"${CASK_ARGS[@]}"}
if [[ "$NOTARIZED" == "1" ]]; then
    printf '%s\n' '<!-- symplast-distribution: notarized -->' > "$DIST/RELEASE-NOTES.md"
    echo 'Universal macOS 14+ apps, signed with Developer ID and notarized by Apple.' >> "$DIST/RELEASE-NOTES.md"
else
    printf '%s\n' '<!-- symplast-distribution: ad-hoc -->' > "$DIST/RELEASE-NOTES.md"
    echo '**Not notarized:** these apps are ad-hoc signed. macOS will warn on first launch. See the installation guide before downloading.' >> "$DIST/RELEASE-NOTES.md"
fi
cat >> "$DIST/RELEASE-NOTES.md" <<'NOTES'

## Downloads

- `Symplast-<version>-bundled.dmg`: recommended easy install; includes non-SSPL Mutagen and its supported remote agents. No separate Mutagen setup. Apple Silicon and Intel, macOS 14+.
- `Symplast-<version>.dmg`: app only (without Mutagen); for people who already have Mutagen installed, or want to manage it separately.
- `SHA256SUMS`: checksums for both disk images.
- `symplast.rb`: Homebrew cask generated from the final bundled disk image.

Drag Symplast to Applications. The app lives in the menu bar, not the Dock.
Never disable Gatekeeper globally or remove quarantine attributes to install it.

[Installation and first-launch help](https://github.com/dylbertram/symplast/blob/main/docs/installation.md)
NOTES
cat "$ROOT/build/mutagen/licenses/Mutagen-SOURCE.txt" >> "$DIST/RELEASE-NOTES.md"

echo "==> Artifacts in $DIST"
ls -1 "$DIST"
