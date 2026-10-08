#!/usr/bin/env python3
"""Reject SSPL/mixed builds; inspect the CLI and every archived agent's Go metadata."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
# All v0.18.1 release targets except obsolete windows/arm (removed by Go 1.26).
AGENTS = set("""aix_ppc64 darwin_amd64 darwin_arm64 dragonfly_amd64
freebsd_386 freebsd_amd64 freebsd_arm freebsd_arm64
linux_386 linux_amd64 linux_arm linux_arm64 linux_mips linux_mipsle
linux_mips64 linux_mips64le linux_ppc64 linux_ppc64le linux_riscv64 linux_s390x
netbsd_386 netbsd_amd64 netbsd_arm netbsd_arm64
openbsd_386 openbsd_amd64 openbsd_arm openbsd_arm64
solaris_amd64 windows_386 windows_amd64 windows_arm64""".split())


def aix_metadata(binary):
    # go version -m rejects stripped XCOFF files (upstream release uses -s -w).
    # Decode Go's documented 1.18+ inline build-info record instead; no agent
    # is executed. Header layout: go.dev/src/debug/buildinfo/buildinfo.go.
    data = Path(binary).read_bytes()
    if not data.startswith(b"\x01\xf7"):
        raise ValueError("AIX agent is not a 64-bit XCOFF executable")
    magic = b"\xff Go buildinf:"
    offsets = [match.start() for match in re.finditer(re.escape(magic), data)
               if match.start() % 16 == 0 and match.start() + 32 <= len(data)
               and data[match.start() + 15] & 2]
    if len(offsets) != 1:
        raise ValueError("AIX agent has missing/ambiguous Go build information")

    def read_string(offset):
        length = 0
        for index in range(10):
            if offset >= len(data):
                break
            byte = data[offset]
            offset += 1
            length |= (byte & 127) << (7 * index)
            if not byte & 128:
                end = offset + length
                if end > len(data):
                    break
                return data[offset:end], end
        raise ValueError("Truncated AIX Go build information")

    version, offset = read_string(offsets[0] + 32)
    module, _ = read_string(offset)
    if len(module) < 33 or module[-17] != 10:
        raise ValueError("AIX module information has invalid framing")
    return f"{binary}: {version.decode('utf-8')}\n{module[16:-16].decode('utf-8')}"


def read_metadata(binary, target):
    if target == "aix_ppc64":
        return aix_metadata(binary)
    return subprocess.check_output(["go", "version", "-m", str(binary)], text=True, stderr=subprocess.STDOUT)


def check_metadata(text, tag, target, go_version):
    if not re.search(rf": go{re.escape(go_version)}\s*$", text, re.MULTILINE):
        raise ValueError(f"Unexpected Go toolchain for {target}")
    settings = dict(re.findall(r"^\s*build\s+(\S+?)=(.*)$", text, re.MULTILINE))
    tags = settings.get("-tags", "").strip('"').split(",")
    if tags != [tag]:
        raise ValueError(f"Unexpected build tags for {target}: {tags}")
    if "mutagensspl" in text or "/sspl" in text.lower():
        raise ValueError(f"SSPL enhancements found in {target}")
    package = "mutagen" if tag == "mutagencli" else "mutagen-agent"
    if not re.search(rf"^\s*path\s+github\.com/mutagen-io/mutagen/cmd/{package}\s*$", text, re.MULTILINE):
        raise ValueError(f"Wrong executable package in {target}")
    os_name, arch = target.split("_")
    if settings.get("GOOS") != os_name or settings.get("GOARCH") != arch:
        raise ValueError(f"Wrong architecture in {target}")
    if settings.get("CGO_ENABLED") != ("1" if os_name == "darwin" else "0"):
        raise ValueError(f"Incorrect cgo/FSEvents configuration in {target}")


def check_members(members):
    if len(members) != len(AGENTS) or {entry.name for entry in members} != AGENTS:
        raise ValueError("Agent archive does not contain the complete supported target set")
    if any(not entry.isfile() for entry in members):
        raise ValueError("Agent archive must contain only regular executable files")


def verify(directory, signed=False, licenses=None):
    directory = Path(directory)
    licenses = Path(licenses) if licenses else directory / "licenses"
    pin = json.loads((ROOT / "scripts/mutagen-source.json").read_text())
    if json.loads((licenses / "Mutagen-BUILD.json").read_text()) != pin:
        raise ValueError("Missing or stale non-SSPL source build provenance; rebuild Mutagen")
    if (licenses / "Mutagen-BUILD-PATCH.diff").read_bytes() != (ROOT / "scripts/mutagen-0.18.1.patch").read_bytes():
        raise ValueError("Source compatibility patch does not match the reviewed build")
    legal = (licenses / "Mutagen-Legal.txt").read_text()
    if "Server Side Public License" in legal or "SSPL-Licensed Enhancements" in legal:
        raise ValueError("Bundled legal output contains SSPL; rebuild from source")
    if "MIT License" not in legal:
        raise ValueError("Missing Mutagen legal notices")
    # This subcommand prints a version only, without contacting/starting a daemon.
    version = subprocess.check_output([str(directory / "mutagen"), "version"], text=True).strip()
    if version != pin["version"]:
        raise ValueError(f"Unexpected Mutagen version: {version}")
    if subprocess.check_output([str(directory / "mutagen"), "legal"], text=True) != legal:
        raise ValueError("Legal notices do not match the executable")
    with tempfile.TemporaryDirectory(prefix="symplast-mutagen-verify-") as temp:
        temp = Path(temp)
        for arch in ["amd64", "arm64"]:
            binary = temp / f"cli_{arch}"
            subprocess.run(["lipo", str(directory / "mutagen"), "-thin",
                            "x86_64" if arch == "amd64" else arch, "-output", str(binary)], check=True)
            text = read_metadata(binary, f"darwin_{arch}")
            check_metadata(text, "mutagencli", f"darwin_{arch}", pin["go_version"])
        with tarfile.open(directory / "mutagen-agents.tar.gz", "r:gz") as archive:
            members = archive.getmembers()
            check_members(members)
            for entry in members:
                binary = temp / entry.name
                with archive.extractfile(entry) as source, binary.open("wb") as output:
                    while chunk := source.read(1024 * 1024):
                        output.write(chunk)
                text = read_metadata(binary, entry.name)
                check_metadata(text, "mutagenagent", entry.name, pin["go_version"])
                if signed and entry.name.startswith("darwin_"):
                    subprocess.run(["codesign", "--verify", "--strict", str(binary)], check=True)
                    signature = subprocess.check_output(["codesign", "-d", "--verbose=4", str(binary)], stderr=subprocess.STDOUT, text=True)
                    if "Authority=Developer ID Application:" not in signature or "runtime" not in signature or "Timestamp=" not in signature:
                        raise ValueError(f"Agent lacks Developer ID/runtime/timestamp: {entry.name}")
                binary.unlink()
    print(f"Verified non-SSPL Mutagen {pin['version']}: both CLI slices + {len(AGENTS)} agents")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--signed", action="store_true")
    parser.add_argument("--licenses", type=Path)
    args = parser.parse_args()
    verify(args.directory, args.signed, args.licenses)
