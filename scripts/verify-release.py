#!/usr/bin/env python3
"""Verify the packaged apps inside both final macOS disk images without launching them."""
import argparse
import plistlib
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def verify(version, notarized=False):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Version must be x.y.z")
    subprocess.run(["shasum", "-a", "256", "-c", "SHA256SUMS"], cwd=ROOT / "dist", check=True)
    for bundled in [False, True]:
        suffix = "-bundled" if bundled else ""
        dmg = ROOT / "dist" / f"Symplast-{version}{suffix}.dmg"
        run("hdiutil", "verify", dmg)
        with tempfile.TemporaryDirectory(prefix="symplast-verify-", dir=ROOT / "build") as work:
            mount = Path(work) / "volume"
            mount.mkdir()
            run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, dmg)
            try:
                app = mount / "Symplast.app"
                resources = app / "Contents/Resources"
                with (app / "Contents/Info.plist").open("rb") as stream:
                    info = plistlib.load(stream)
                assert info["CFBundleIdentifier"] == "com.dylanbertram.symplast"
                assert info["CFBundleShortVersionString"] == version
                assert info["CFBundleVersion"] == version
                assert info["LSMinimumSystemVersion"] == "14.0"
                assert (mount / "Applications").is_symlink()
                assert (mount / "Applications").readlink() == Path("/Applications")
                for name in ["AppIcon.icns", "AppLogo.png", "LICENSE", "THIRD-PARTY-NOTICES.md"]:
                    assert (resources / name).is_file(), name
                run("codesign", "--verify", "--deep", "--strict", app)
                binaries = [app / "Contents/MacOS/Symplast"]
                if bundled:
                    binaries.append(resources / "mutagen")
                    for name in ["mutagen-agents.tar.gz", "Mutagen-Licenses/Mutagen-Legal.txt", "Mutagen-Licenses/Mutagen-SOURCE.txt", "Mutagen-Licenses/Mutagen-BUILD.json", "Mutagen-Licenses/Mutagen-LICENSE.txt", "Mutagen-Licenses/Mutagen-BUILD-PATCH.diff"]:
                        assert (resources / name).is_file(), name
                    args = ["--signed"] if notarized else []
                    run("python3", ROOT / "scripts/verify-mutagen.py", resources,
                        "--licenses", resources / "Mutagen-Licenses", *args)
                else:
                    assert not (resources / "mutagen").exists()
                for binary in binaries:
                    for arch in ["arm64", "x86_64"]:
                        run("lipo", binary, "-verify_arch", arch)
                # Info.plist alone cannot make a binary built for a newer OS
                # compatible with Sonoma. Check the actual Mach-O load commands.
                build_info = subprocess.check_output(
                    ["xcrun", "vtool", "-show-build", str(binaries[0])], text=True)
                minimums = re.findall(r"^\s*minos\s+([0-9.]+)", build_info, re.MULTILINE)
                assert minimums and all(tuple(map(int, value.split(".")[:2])) == (14, 0) for value in minimums), build_info
                if notarized:
                    run("xcrun", "stapler", "validate", app)
                    run("xcrun", "stapler", "validate", dmg)
                    run("spctl", "--assess", "--type", "execute", app)
                print(f"Verified {dmg.name}: universal app, bundle metadata, resources, signature and checksums")
            finally:
                run("hdiutil", "detach", mount)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("--notarized", action="store_true")
    args = parser.parse_args()
    verify(args.version, args.notarized)
