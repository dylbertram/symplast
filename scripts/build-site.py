#!/usr/bin/env python3
"""Prepare public assets and validated release data, then prerender the Svelte site."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "https://github.com/dylbertram/symplast"
STATIC_FILES = ("_headers", "_redirects", "robots.txt", "sitemap.xml")
ASSETS = (("Resources/AppLogo.png", "mark.png"),
          ("Resources/AppIcon-1024.png", "app-icon.png"),
          ("docs/images/sessions-light.png", "sessions-light.png"),
          ("docs/images/sessions-dark.png", "sessions-dark.png"))


def release_data(release=None, homebrew_ready=False):
    data = {"available": False, "version": None, "download": None,
            "app_only_download": None, "notes": None,
            "notarized": False, "homebrew_ready": False}
    if not release or release.get("draft", True) or release.get("prerelease", True):
        return data
    tag = release.get("tag_name", "")
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        return data
    version = tag[1:]
    filenames = [f"Symplast-{version}-bundled.dmg", f"Symplast-{version}.dmg", "SHA256SUMS"]
    base = f"{REPOSITORY}/releases/download/{tag}"
    assets = {asset.get("name"): asset.get("browser_download_url") for asset in release.get("assets", [])}
    if not all(assets.get(name) == f"{base}/{name}" for name in filenames):
        return data
    return {"available": True, "version": version,
            "download": f"{base}/{filenames[0]}", "app_only_download": f"{base}/{filenames[1]}",
            "notes": f"{REPOSITORY}/releases/tag/{tag}",
            "notarized": "<!-- symplast-distribution: notarized -->" in (release.get("body") or ""),
            "homebrew_ready": bool(homebrew_ready)}


def prepare(release=None, homebrew_ready=False):
    # Only these public assets and validated fields enter the website build.
    assets = ROOT / "site/static/assets"
    assets.mkdir(parents=True, exist_ok=True)
    for source, name in ASSETS:
        shutil.copy2(ROOT / source, assets / name)
    generated = ROOT / "site/src/lib/generated"
    generated.mkdir(parents=True, exist_ok=True)
    (generated / "release.json").write_text(json.dumps(release_data(release, homebrew_ready), indent=2) + "\n")


def build(release=None, homebrew_ready=False):
    prepare(release, homebrew_ready)
    allowed = {ROOT / "site/static" / name for name in STATIC_FILES}
    allowed.update(ROOT / "site/static/assets" / name for _, name in ASSETS)
    unexpected = [path for path in (ROOT / "site/static").rglob("*") if path.is_file() and path not in allowed]
    if unexpected:
        raise ValueError(f"Unexpected public files; refusing to upload: {unexpected}")
    subprocess.run(["npm", "run", "build"], cwd=ROOT / "site", check=True)
    print(f"Website ready: {ROOT / 'dist/site'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-metadata", type=Path)
    parser.add_argument("--homebrew-ready", action="store_true")
    parser.add_argument("--prepare-only", action="store_true", help="Prepare assets and release data for Vite development")
    args = parser.parse_args()
    release = json.loads(args.release_metadata.read_text()) if args.release_metadata else None
    (prepare if args.prepare_only else build)(release, args.homebrew_ready)
