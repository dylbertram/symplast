# Installing Symplast

Symplast runs on **macOS 14 Sonoma or newer**, on Apple Silicon and Intel Macs.
Public releases are available from [GitHub Releases](https://github.com/dylbertram/symplast/releases).
Until the first public release is published, build from source using the [build guide](building.md).

## Disk image

Choose one of the two disk images from the same release:

| Download | Best for |
| --- | --- |
| **With Mutagen** — `Symplast-<version>-bundled.dmg` | **Recommended.** Everything included; no separate Mutagen installation or terminal setup. |
| **Without Mutagen** — `Symplast-<version>.dmg` | Smaller app-only download, for people who already have Mutagen or want to install/manage it separately. |

Both contain the same app and support Apple Silicon and Intel Macs. Install
only one; they use the same app name and preferences.

1. Download your chosen disk image. If unsure, choose **With Mutagen**.
2. Open the disk image and drag **Symplast.app** to **Applications**.
3. Eject the disk image, then open Symplast from Applications or Spotlight.
4. Click its **menu bar icon**. It does not appear in the Dock.

The self-contained app includes a non-SSPL source build of Mutagen and its supported
remote agent bundle (all upstream targets except obsolete Windows ARM32). The
app-only variant includes neither. For SSH targets, it still
uses your SSH configuration and agent, and shares Mutagen's existing daemon and
sessions. See [SSH authentication](authentication.md) before using remote targets.

## First launch and Gatekeeper

**Public releases are intended to be Developer ID signed and notarized by Apple.**
Check each release's notes for its actual status. A notarized app normally shows
the standard confirmation that it was downloaded from the Internet.

Development/ad-hoc builds are **not notarized**. A disk image does not remove
Gatekeeper's checks, and Homebrew does not make an app notarized. macOS can
refuse to open these builds because the developer cannot be verified.

Only if you trust the download and have verified its source:

1. Attempt to open Symplast from Applications.
2. Open **System Settings → Privacy & Security**.
3. Use **Open Anyway** for Symplast and confirm **Open**.

Do **not** disable Gatekeeper or strip quarantine attributes. If macOS reports
malware, a revoked signature, or a damaged app, do not bypass that warning;
download again from the official release and report the problem. Managed Macs
may not allow an override. Apple's [first-launch guide](https://support.apple.com/en-us/102445)
explains the different warnings.

Each release states whether it is notarized. Never assume a local or testing
build has been notarized just because the publisher has a developer membership.

## Verify a download

Download `SHA256SUMS` and the disk image from the **same release**, place them in
one folder, and compare the relevant entry with:

```sh
shasum -a 256 Symplast-<version>-bundled.dmg
```

Checksums detect corruption; they are not a substitute for trusting the publisher
or for Apple's notarization checks.

## Homebrew

Once the public tap is activated:

```sh
brew install --cask dylbertram/symplast/symplast
```

The cask installs the self-contained app. Upgrade with `brew upgrade --cask symplast`.
The tap is separate from Homebrew's official `homebrew/cask` collection.
Before the tap is published, this command is not available.

## Uninstall

Quit Symplast and remove `/Applications/Symplast.app`, or run
`brew uninstall --cask symplast`. This does **not** terminate Mutagen's daemon or
delete its running sessions or files. Homebrew's optional `--zap` also removes
Symplast's preferences and remembered definitions; those definitions are not backups.
