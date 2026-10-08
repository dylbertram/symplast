#!/usr/bin/env python3
"""Verify the prerendered site, local assets, and release-dependent download state."""
from html.parser import HTMLParser
import json
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "dist/site"


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.fragments, self.assets, self.links = set(), set(), set(), set()
        self.text = []
        self.csp = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        href = attrs.get("href", "")
        if href.startswith("#"):
            self.fragments.add(href[1:])
        if tag == "a":
            self.links.add(href)
        if tag == "link" and attrs.get("rel") in ["stylesheet", "modulepreload", "icon"]:
            self.assets.add(href)
        if tag in ["img", "script"] and attrs.get("src"):
            self.assets.add(attrs["src"])
        if tag == "source":
            self.assets.add(attrs["srcset"])
        if tag == "meta" and attrs.get("http-equiv", "").lower() == "content-security-policy":
            self.csp = attrs["content"]
        if tag == "svg":
            assert attrs.get("aria-hidden") == "true", "Icons must be decorative"

    def handle_data(self, text):
        self.text.append(text)


def verify():
    release = json.loads((ROOT / "site/src/lib/generated/release.json").read_text())
    for name in ["index.html", "privacy.html"]:
        html = (OUTPUT / name).read_text()
        page = Page()
        page.feed(html)
        assert page.fragments.issubset(page.ids), f"Broken fragment on {name}"
        for link in page.links:
            if link.startswith("/") and not link.startswith("//"):
                path = urlsplit(link).path.lstrip("/") or "index.html"
                assert (OUTPUT / path).is_file(), f"Broken local page link: {link}"
        for asset in page.assets:
            path = urlsplit(asset).path.lstrip("/")
            assert (OUTPUT / path).is_file(), f"Missing asset: {asset}"
        assert page.csp and "sha256-" in page.csp, "Missing hashed hydration CSP"
        text = " ".join(page.text)
        for retired in ["quietly", "Make yourself", "Everyday controls", "Your sessions, at a glance", "Less to remember"]:
            assert retired not in text, f"Retired copy: {retired}"
        if name == "index.html":
            if release["available"]:
                assert release["download"] in page.links
                assert release["app_only_download"] in page.links
                assert ("not notarized" in text) == (not release["notarized"])
            else:
                assert "Coming soon" in text
                assert not any(".dmg" in link for link in page.links)
            assert ("brew install --cask" in text) == release["homebrew_ready"]
    forbidden = {"release.env", "package.json", "package-lock.json", "private-notes.md"}
    for path in OUTPUT.rglob("*"):
        assert path.name not in forbidden and not path.name.startswith(".env"), f"Private build file: {path}"
    print("Prerendered pages, assets, CSP, and download state verified.")


if __name__ == "__main__":
    verify()
