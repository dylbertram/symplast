"""Portable regression tests for release metadata, public HTML, and cask generation."""
import hashlib
from html.parser import HTMLParser
import importlib.util
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), ROOT / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


site = load("build-site")
cask = load("generate-cask")
mutagen = load("verify-mutagen")


class ReleaseToolsTests(unittest.TestCase):
    def metadata(self, tags="mutagenagent", os_name="linux", arch="amd64", cgo="0"):
        return f'''fixture: go1.26.8
    path github.com/mutagen-io/mutagen/cmd/{"mutagen" if tags.startswith("mutagencli") else "mutagen-agent"}
    build -tags={tags}
    build CGO_ENABLED={cgo}
    build GOOS={os_name}
    build GOARCH={arch}
'''

    def test_non_sspl_metadata_and_macos_fsevents_are_accepted(self):
        mutagen.check_metadata(self.metadata(), "mutagenagent", "linux_amd64", "1.26.8")
        mutagen.check_metadata(self.metadata("mutagencli", "darwin", "arm64", "1"),
                               "mutagencli", "darwin_arm64", "1.26.8")

    def test_sspl_wrong_targets_and_missing_cgo_are_rejected(self):
        for text in [self.metadata("mutagenagent,mutagensspl"),
                     self.metadata("mutagencli"), self.metadata(arch="arm64"),
                     self.metadata(cgo="1"), self.metadata().replace("go1.26.8", "go1.23.0")]:
            with self.assertRaises(ValueError):
                mutagen.check_metadata(text, "mutagenagent", "linux_amd64", "1.26.8")
        with self.assertRaises(ValueError):
            mutagen.check_metadata(self.metadata("mutagenagent", "darwin", "arm64", "0"),
                                   "mutagenagent", "darwin_arm64", "1.26.8")

    def test_agent_archive_requires_every_supported_target_and_no_links(self):
        members = [tarfile.TarInfo(name) for name in sorted(mutagen.AGENTS)]
        mutagen.check_members(members)
        for bad in [members[:-1], members + [members[0]],
                    members + [tarfile.TarInfo("../escape")]]:
            with self.assertRaises(ValueError):
                mutagen.check_members(bad)
        members[0].type = tarfile.SYMTYPE
        with self.assertRaises(ValueError):
            mutagen.check_members(members)

    def test_old_sspl_or_stale_builds_are_rejected_before_executing(self):
        with tempfile.TemporaryDirectory() as temp:
            licenses = Path(temp) / "licenses"
            licenses.mkdir()
            pin = json.loads((ROOT / "scripts/mutagen-source.json").read_text())
            (licenses / "Mutagen-BUILD.json").write_text(json.dumps(pin))
            (licenses / "Mutagen-BUILD-PATCH.diff").write_bytes((ROOT / "scripts/mutagen-0.18.1.patch").read_bytes())
            (licenses / "Mutagen-Legal.txt").write_text("MIT License\nServer Side Public License")
            with patch.object(mutagen.subprocess, "check_output") as command:
                with self.assertRaisesRegex(ValueError, "SSPL"):
                    mutagen.verify(temp)
                command.assert_not_called()
                pin["version"] = "0.17.0"
                (licenses / "Mutagen-BUILD.json").write_text(json.dumps(pin))
                with self.assertRaisesRegex(ValueError, "stale"):
                    mutagen.verify(temp)
                command.assert_not_called()

    def test_stripped_aix_build_info_is_read_without_executing_agent(self):
        def varint(value):
            result = bytearray()
            while value >= 128:
                result.append((value & 127) | 128)
                value >>= 7
            result.append(value)
            return bytes(result)

        version = b"go1.26.8"
        module = b"s" * 16 + self.metadata(os_name="aix", arch="ppc64").split("\n", 1)[1].encode() + b"e" * 16
        data = (b"\x01\xf7" + b"\0" * 14 + b"\xff Go buildinf:" + b"\x08\x03" + b"\0" * 16
                + varint(len(version)) + version + varint(len(module)) + module)
        with tempfile.TemporaryDirectory() as temp:
            binary = Path(temp) / "aix_ppc64"
            binary.write_bytes(data)
            with patch.object(mutagen.subprocess, "check_output") as command:
                text = mutagen.read_metadata(binary, "aix_ppc64")
                mutagen.check_metadata(text, "mutagenagent", "aix_ppc64", "1.26.8")
                command.assert_not_called()
            for invalid in [data[:-1], data[:40], b"not an executable"]:
                binary.write_bytes(invalid)
                with self.assertRaises(ValueError):
                    mutagen.aix_metadata(binary)

    def release(self):
        base = f"{site.REPOSITORY}/releases/download/v1.2.3"
        return {"tag_name": "v1.2.3", "draft": False, "prerelease": False, "body": "",
                "assets": [{"name": name, "browser_download_url": f"{base}/{name}"}
                           for name in ["Symplast-1.2.3-bundled.dmg", "Symplast-1.2.3.dmg", "SHA256SUMS"]]}

    def test_no_release_does_not_advertise_download_or_brew(self):
        values = site.release_data(homebrew_ready=True)
        self.assertFalse(values["available"])
        self.assertFalse(values["homebrew_ready"])
        self.assertIsNone(values["download"])

    def test_public_release_enables_the_exact_versioned_download(self):
        values = site.release_data(self.release(), homebrew_ready=True)
        self.assertEqual(values["download"], f"{site.REPOSITORY}/releases/download/v1.2.3/Symplast-1.2.3-bundled.dmg")
        self.assertEqual(values["app_only_download"], f"{site.REPOSITORY}/releases/download/v1.2.3/Symplast-1.2.3.dmg")
        self.assertTrue(values["homebrew_ready"])
        self.assertFalse(values["notarized"])

    def test_both_dmg_options_must_exist_before_advertising_downloads(self):
        for missing in ["Symplast-1.2.3.dmg", "Symplast-1.2.3-bundled.dmg"]:
            release = self.release()
            release["assets"] = [asset for asset in release["assets"] if asset["name"] != missing]
            self.assertFalse(site.release_data(release)["available"])

    def test_download_icons_are_decorative_and_links_keep_text_labels(self):
        class Icons(HTMLParser):
            def __init__(self):
                super().__init__()
                self.icons = []
            def handle_starttag(self, tag, attrs):
                if tag == "svg":
                    self.icons.append(dict(attrs))
        button = (ROOT / "site/src/lib/DownloadButton.svelte").read_text()
        html = (ROOT / "site/src/routes/+page.svelte").read_text()
        self.assertIn("Download for macOS", button)
        self.assertIn("Direct download", html)
        self.assertIn("Download app only (without Mutagen)", html)
        parser = Icons()
        parser.feed((ROOT / "site/src/lib/Icon.svelte").read_text())
        self.assertEqual(len(parser.icons), 1)
        for icon in parser.icons:
            self.assertEqual(icon.get("aria-hidden"), "true")
            self.assertEqual(icon.get("focusable"), "false")

    def test_brew_not_advertised_until_tap_is_ready(self):
        self.assertFalse(site.release_data(self.release())["homebrew_ready"])

    def test_drafts_prereleases_and_incomplete_assets_are_not_downloadable(self):
        for change in [{"draft": True}, {"prerelease": True}, {"assets": []}, {"tag_name": "v1.2.3-beta"}]:
            release = self.release()
            release.update(change)
            self.assertFalse(site.release_data(release)["available"])

    def test_untrusted_download_urls_are_not_used(self):
        release = self.release()
        release["assets"][0]["browser_download_url"] = 'javascript:alert("hello")'
        self.assertFalse(site.release_data(release)["available"])

    def test_signed_notice_requires_explicit_notarized_marker(self):
        release = self.release()
        release["body"] = "signed"
        self.assertFalse(site.release_data(release)["notarized"])
        release["body"] = "<!-- symplast-distribution: notarized -->"
        self.assertTrue(site.release_data(release)["notarized"])

    def test_site_copy_focuses_on_convenience(self):
        for name in ["routes/+page.svelte", "lib/Footer.svelte"]:
            html = (ROOT / "site/src" / name).read_text()
            for retired_copy in ["quiet", "Make yourself", "A note about", "SIGNING_NOTICE", "Everyday controls", "Your sessions, at a glance", "Less to remember"]:
                self.assertNotIn(retired_copy, html)

    def test_local_fragment_links_resolve(self):
        class Links(HTMLParser):
            def __init__(self):
                super().__init__()
                self.ids, self.fragments = set(), set()
            def handle_starttag(self, tag, attrs):
                attrs = dict(attrs)
                if "id" in attrs:
                    self.ids.add(attrs["id"])
                if attrs.get("href", "").startswith("#"):
                    self.fragments.add(attrs["href"][1:])
        html = (ROOT / "site/src/routes/+page.svelte").read_text()
        html += (ROOT / "site/src/routes/+layout.svelte").read_text()
        parser = Links()
        parser.feed(html)
        self.assertTrue(parser.fragments.issubset(parser.ids))

    def test_only_allowlisted_site_files_can_be_uploaded(self):
        self.assertEqual(set(site.STATIC_FILES), {"_headers", "_redirects", "robots.txt", "sitemap.xml"})
        self.assertEqual(set((ROOT / "site/static").iterdir()) - {ROOT / "site/static/assets"},
                         {ROOT / "site/static" / name for name in site.STATIC_FILES})

    def test_site_build_never_copies_accidental_private_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "site").mkdir()
            (root / "site/.env").write_text("PRIVATE_TOKEN=do-not-upload")
            (root / "site/private-notes.md").write_text("do-not-upload")
            for name in ["Resources/AppLogo.png", "Resources/AppIcon-1024.png",
                         "docs/images/sessions-light.png", "docs/images/sessions-dark.png"]:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"fixture")
            with patch.object(site, "ROOT", root):
                release = self.release()
                release["private_token"] = "do-not-upload"
                site.prepare(release)
            output = root / "site/static"
            self.assertFalse((output / ".env").exists())
            self.assertFalse((output / "private-notes.md").exists())
            self.assertTrue((output / "assets/app-icon.png").exists())
            data = (root / "site/src/lib/generated/release.json").read_text()
            self.assertNotIn("do-not-upload", data)
            self.assertEqual(json.loads(data), site.release_data(release))

    def test_cask_uses_final_dmg_hash_and_warns_for_ad_hoc_builds(self):
        with tempfile.TemporaryDirectory() as temp:
            dmg = Path(temp) / "release.dmg"
            output = Path(temp) / "symplast.rb"
            dmg.write_bytes(b"final disk image including stapled signature")
            subprocess.run(["python3", str(ROOT / "scripts/generate-cask.py"), "1.2.3", str(dmg), "--output", str(output)], check=True)
            text = output.read_text()
            self.assertIn(hashlib.sha256(dmg.read_bytes()).hexdigest(), text)
            self.assertIn('version "1.2.3"', text)
            self.assertIn("not notarized", text)
            self.assertNotIn("xattr", text)
            self.assertNotIn("no-quarantine", text)

    def test_notarized_cask_omits_unsigned_warning(self):
        self.assertNotIn("not notarized", cask.render("1.2.3", "a" * 64, notarized=True))

    def test_invalid_cask_versions_and_checksums_are_rejected(self):
        for version in ["../1.0.0", "1.0.0\"", "v1.0.0", "1.0.0-beta"]:
            with self.assertRaises(ValueError):
                cask.render(version, "a" * 64)
        with self.assertRaises(ValueError):
            cask.render("1.0.0", "dummy")


if __name__ == "__main__":
    unittest.main()
