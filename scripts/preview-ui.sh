#!/usr/bin/env bash
# Render isolated light/dark UI fixtures without running Mutagen.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${1:-$ROOT/.report/ui-refinement}"
mkdir -p "${TMPDIR%/}/opencode"
TEMP="$(mktemp -d "${TMPDIR%/}/opencode/symplast-preview.XXXXXX")"
swiftc -D DEBUG "$ROOT"/Sources/Symplast/{Models,Services,Support,Views}/*.swift \
    "$ROOT/scripts/preview-ui.swift" -o "$TEMP/preview-ui"
"$TEMP/preview-ui" "$OUTPUT" "${@:2}"
