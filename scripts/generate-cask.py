#!/usr/bin/env python3
"""Generate a tap-ready cask from the exact final release DMG (never a dummy hash)."""
import argparse
import hashlib
from pathlib import Path
import re


def render(version, digest, notarized=False):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Version must be x.y.z")
    if not re.fullmatch(r"[a-f0-9]{64}", digest):
        raise ValueError("Invalid SHA-256")
    caveats = "" if notarized else '''
  caveats <<~EOS
    This release is ad-hoc signed, not notarized by Apple.
    If macOS blocks first launch, review System Settings > Privacy & Security.
    Use Open Anyway only if you trust the download; do not disable Gatekeeper.
  EOS
'''
    return f'''cask "symplast" do
  version "{version}"
  sha256 "{digest}"

  url "https://github.com/dylbertram/symplast/releases/download/v#{{version}}/Symplast-#{{version}}-bundled.dmg"
  name "Symplast"
  desc "Native menu-bar companion for Mutagen folder synchronization"
  homepage "https://symplast.app/"

  depends_on macos: ">= :sonoma"

  app "Symplast.app"

  zap trash: "~/Library/Preferences/com.dylanbertram.symplast.plist"
{caveats}end
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("dmg", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--notarized", action="store_true")
    args = parser.parse_args()
    digest = hashlib.sha256()
    with args.dmg.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(args.version, digest.hexdigest(), args.notarized))


if __name__ == "__main__":
    main()
