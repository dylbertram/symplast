#!/usr/bin/env bash
# Fetch pinned Mutagen source and build a non-SSPL CLI and all supported agents.
# Requires macOS, Xcode Command Line Tools, Python 3, and the pinned Go toolchain.
# No precompiled upstream release binaries are used.
# Build a universal CLI and stage its agent bundle
# for embedding. Outputs to build/mutagen/:
#
#   build/mutagen/mutagen                universal (arm64 + amd64) CLI
#   build/mutagen/mutagen-agents.tar.gz  agent bundle for remote endpoints
#
# Then build the self-contained app with:
#   BUNDLE_MUTAGEN=1 \
#     MUTAGEN_BIN=build/mutagen/mutagen \
#     MUTAGEN_AGENTS=build/mutagen/mutagen-agents.tar.gz \
#     ./scripts/build-app.sh
#
# Update scripts/mutagen-source.json to change the reviewed source/toolchain pin.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/scripts/mutagen-source.json")"
SOURCE_SHA256="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_sha256"])' "$ROOT/scripts/mutagen-source.json")"
GO_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["go_version"])' "$ROOT/scripts/mutagen-source.json")"
OUT="$ROOT/build/mutagen"
TEMP_ROOT="${TMPDIR:-/tmp}/opencode"
mkdir -p "$TEMP_ROOT"
WORK="$(mktemp -d "$TEMP_ROOT/mutagen-fetch.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: invalid Mutagen version" >&2; exit 1; }
[[ "$SOURCE_SHA256" =~ ^[0-9a-f]{64}$ ]] || { echo "error: invalid source checksum" >&2; exit 1; }
[[ "$(uname -s)" == "Darwin" ]] || { echo "error: macOS is required for FSEvents-enabled agents" >&2; exit 1; }
export GOTOOLCHAIN=local
export GOENV=off
export GOWORK=off
# Do not inherit user build tags (especially mutagensspl) or alternate targets.
unset GOFLAGS GOOS GOARCH GOARM GOAMD64 GOEXPERIMENT
[[ "$(go env GOVERSION)" == "go$GO_VERSION" ]] || { echo "error: Go $GO_VERSION is required" >&2; exit 1; }
SOURCE_URL="https://codeload.github.com/mutagen-io/mutagen/tar.gz/refs/tags/v$VERSION"
echo "==> Fetching checksum-pinned Mutagen $VERSION source"
curl -fSL --retry 3 "$SOURCE_URL" -o "$WORK/source.tar.gz"
(cd "$WORK" && printf '%s  source.tar.gz\n' "$SOURCE_SHA256" | shasum -a 256 -c -)
tar -xzf "$WORK/source.tar.gz" -C "$WORK"
SOURCE="$WORK/mutagen-$VERSION"
echo "==> Applying documented compatibility patch (obsolete windows/arm target)"
(cd "$SOURCE" && patch --batch --forward -p1 < "$ROOT/scripts/mutagen-0.18.1.patch")
SIGN_ARGS=()
if [[ -n "${CODESIGN_IDENTITY:-}" && "$CODESIGN_IDENTITY" != "-" ]]; then
    # Sign macOS agents BEFORE upstream puts them inside the tar archive.
    SIGN_ARGS+=(--macos-codesign-identity="$CODESIGN_IDENTITY")
fi
echo "==> Building CLI and agents with --mode=release --sspl=false"
(cd "$SOURCE" && go mod download && go mod verify && \
    go run scripts/build.go --mode=release --sspl=false ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"})

# Stage separately: failed source builds must not leave a mixed old/new bundle.
STAGED="$WORK/staged"
mkdir -p "$STAGED/licenses"

echo "==> Building universal CLI"
lipo -create "$SOURCE/build/cli/darwin_amd64" "$SOURCE/build/cli/darwin_arm64" -output "$STAGED/mutagen"
chmod 755 "$STAGED/mutagen"
echo "    architectures: $(lipo -archs "$STAGED/mutagen")"

echo "==> Staging agent bundle"
cp "$SOURCE/build/mutagen-agents.tar.gz" "$STAGED/mutagen-agents.tar.gz"
"$STAGED/mutagen" legal > "$STAGED/licenses/Mutagen-Legal.txt"
cp "$SOURCE/LICENSE" "$STAGED/licenses/Mutagen-LICENSE.txt"
cp "$ROOT/scripts/mutagen-0.18.1.patch" "$STAGED/licenses/Mutagen-BUILD-PATCH.diff"
cp "$ROOT/scripts/mutagen-source.json" "$STAGED/licenses/Mutagen-BUILD.json"
cat > "$STAGED/licenses/Mutagen-SOURCE.txt" <<SOURCE

## Bundled Mutagen source and licenses

The bundled executable and supported agents are Mutagen $VERSION, built from
checksum-pinned upstream source using Go $GO_VERSION (not official release binaries).
Build command: go run scripts/build.go --mode=release --sspl=false
SSPL enhancements are disabled for BOTH the CLI and all remote agents.
Compatibility patch: omit the obsolete Windows ARM32 agent target removed by Go 1.26.
All other upstream agent targets are included (including macOS Intel and Apple Silicon).
Patch: https://github.com/dylbertram/symplast/blob/main/scripts/mutagen-0.18.1.patch
The exact patch is included beside these notices as Mutagen-BUILD-PATCH.diff.
Source SHA-256: $SOURCE_SHA256
Source and build scripts: https://github.com/mutagen-io/mutagen/tree/v$VERSION
Source archive: https://github.com/mutagen-io/mutagen/archive/refs/tags/v$VERSION.tar.gz
Dependency versions: https://github.com/mutagen-io/mutagen/blob/v$VERSION/go.mod
The complete notices for the compiled non-SSPL code are included in the app's
Contents/Resources/Mutagen-Licenses/Mutagen-Legal.txt. The upstream source is
available at no charge; no source download is required to use the app.
SOURCE
VERIFY_ARGS=()
if [[ -n "${CODESIGN_IDENTITY:-}" && "$CODESIGN_IDENTITY" != "-" ]]; then VERIFY_ARGS+=(--signed); fi
python3 "$ROOT/scripts/verify-mutagen.py" "$STAGED" ${VERIFY_ARGS[@]+"${VERIFY_ARGS[@]}"}
# OUT contains only generated artifacts from this script.
rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
mv "$STAGED" "$OUT"

echo "==> Done: $OUT"
