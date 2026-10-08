#!/usr/bin/env python3
"""Build a dependency-free Pages upload directory, with optional published release data."""
import argparse
from html import escape
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "https://github.com/dylbertram/symplast"
SITE_FILES = ("index.html", "style.css", "privacy.html", "_headers", "_redirects", "robots.txt", "sitemap.xml")


def substitutions(release=None, homebrew_ready=False):
    available = False
    notarized = False
    if release and not release.get("draft", True) and not release.get("prerelease", True):
        tag = release.get("tag_name", "")
        if re.fullmatch(r"v\d+\.\d+\.\d+", tag):
            version = tag[1:]
            filename = f"Symplast-{version}-bundled.dmg"
            download = f"{REPOSITORY}/releases/download/{tag}/{filename}"
            app_only_name = f"Symplast-{version}.dmg"
            app_only_download = f"{REPOSITORY}/releases/download/{tag}/{app_only_name}"
            assets = {asset.get("name"): asset.get("browser_download_url") for asset in release.get("assets", [])}
            available = (assets.get(filename) == download and assets.get(app_only_name) == app_only_download
                         and assets.get("SHA256SUMS") == f"{REPOSITORY}/releases/download/{tag}/SHA256SUMS")
            notarized = "<!-- symplast-distribution: notarized -->" in (release.get("body") or "")
    if available:
        cta = f'<a class="button" href="{escape(download)}">Download for Mac <span aria-hidden="true">↓</span></a>'
        downloads = f'''<div class="install-option"><h3>Download the disk image</h3>{cta}<p>Recommended easy install · Includes Mutagen<br>Version {escape(version)} · Apple Silicon &amp; Intel</p><p>Open the disk image and drag Symplast to Applications. No separate Mutagen installation needed.</p><a class="secondary-download" href="{escape(app_only_download)}">Download app only (without Mutagen) ↓</a><p>Already use Mutagen? Choose the smaller app-only download and keep your existing installation.</p><a class="secondary-download" href="{REPOSITORY}/releases/tag/{escape(tag)}">Checksums &amp; release notes ↗</a></div>'''
    else:
        cta = '<a class="button" href="#downloads">Coming soon <span aria-hidden="true">↘</span></a>'
        downloads = f'''<div class="install-option"><h3>A quiet debut, coming soon.</h3><p>The first public release is being prepared. Downloads will appear here when they’re ready.</p><a class="secondary-download" href="{REPOSITORY}">Follow the project on GitHub ↗</a></div>'''
    homebrew = '<code>brew install --cask dylbertram/symplast/symplast</code><p>Installs the self-contained app from our public tap.</p>' if available and homebrew_ready else '<p>The Homebrew tap is being prepared alongside the first release.</p>'
    if available and notarized:
        notice = '<p><strong>This release is signed and notarized by Apple.</strong> macOS will ask you to confirm opening a downloaded app.</p>'
    elif available:
        notice = '<p><strong>This build is not notarized by Apple.</strong> macOS may block first launch. Only if you trust the download, attempt to open it, then choose <strong>System Settings → Privacy &amp; Security → Open Anyway</strong>. Never disable Gatekeeper or bypass a malware or damaged-app warning.</p>'
    else:
        notice = '<p><strong>Public downloads are being prepared for Developer ID signing and Apple notarization.</strong> Check the release notes for the status of the build you download. Development builds may be blocked by macOS; never disable Gatekeeper to install them.</p>'
    return {"HERO_CTA": cta, "DOWNLOADS": downloads, "HOMEBREW": homebrew, "SIGNING_NOTICE": notice}


def build(release=None, homebrew_ready=False):
    output = ROOT / "dist/site"
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    for name in SITE_FILES:
        shutil.copy2(ROOT / "site" / name, output / name)
    html = (output / "index.html").read_text()
    for key, value in substitutions(release, homebrew_ready).items():
        html = html.replace(f"@@{key}@@", value)
    if re.search(r"@@\w+@@", html):
        raise ValueError("Unresolved site template token")
    (output / "index.html").write_text(html)
    assets = output / "assets"
    assets.mkdir()
    for source, name in [("Resources/AppLogo.png", "mark.png"),
                         ("Resources/AppIcon-1024.png", "app-icon.png"),
                         ("docs/images/sessions-light.png", "sessions-light.png"),
                         ("docs/images/sessions-dark.png", "sessions-dark.png")]:
        shutil.copy2(ROOT / source, assets / name)
    print(f"Website ready: {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-metadata", type=Path)
    parser.add_argument("--homebrew-ready", action="store_true")
    args = parser.parse_args()
    release = json.loads(args.release_metadata.read_text()) if args.release_metadata else None
    build(release, args.homebrew_ready)
