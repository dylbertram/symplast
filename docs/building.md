# Building Symplast: logo and app

This document explains the two things that are easy to mix up:

1. **The brand mark** — how `logo.svg` becomes the menu-bar glyph and the app icon.
2. **The app build** — how the Swift package becomes a `.app`, and the two
   distribution shapes.

If you only want the short version:

```sh
# 1. put your mark at the repo root
cp branding/symplast-mark.svg logo.svg

# 2. build the app (regenerates the logo + icon for you)
bash scripts/build-app.sh
open build/Symplast.app
```

## 1. The brand mark

### One source of truth: `logo.svg`

`logo.svg` at the repo root is the only mark the build reads. Everything else is
generated from it:

```
logo.svg
   │  scripts/make-logo.swift           (AppKit SVG render)
   ▼
Resources/AppLogo.png                    (1024×1024, transparent)
   │  scripts/make-icon.swift            (rounded tile + mark)
   ▼
Resources/AppIcon-1024.png  ──►  AppIcon.icns   (inside the .app)
```

`Resources/AppLogo.png` is also copied into the app bundle as `AppLogo.png`,
which is what the running app loads for the menu-bar glyph.

### What the scripts do

| Script                    | Input                   | Output                       | Notes                                                                                                                                                           |
| ------------------------- | ----------------------- | ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/make-logo.swift` | `logo.svg`              | `Resources/AppLogo.png`      | Renders **any valid SVG** via AppKit's native SVG support. Curves, transforms and colours are preserved. The mark is aspect-fit and centred on a square canvas. |
| `scripts/make-icon.swift` | `Resources/AppLogo.png` | `Resources/AppIcon-1024.png` | Composites the mark at 70% over a rounded, dark-gradient "squircle".                                                                                            |

Run them by hand if you want:

```sh
swift scripts/make-logo.swift logo.svg Resources/AppLogo.png 1024
swift scripts/make-icon.swift Resources/AppLogo.png Resources/AppIcon-1024.png 1024
```

### When the build regenerates them

`scripts/build-app.sh` is lazy, so a normal build is fast:

- It renders `AppLogo.png` only when `logo.svg` is **newer** than `AppLogo.png`.
- It builds `AppIcon-1024.png` only when `AppLogo.png` is **newer** than it.

So after editing `logo.svg`, a plain `./scripts/build-app.sh` picks it up. If it
does not, force it:

```sh
rm -f Resources/AppLogo.png Resources/AppIcon-1024.png
./scripts/build-app.sh
```

Both `Resources/AppLogo.png` and `Resources/AppIcon-1024.png` are committed, so
the app has a logo even before the generator runs.

### Mark requirements and gotchas

- **Keep the background transparent.** The menu bar treats the PNG as a
  _template_ image: macOS throws away the colour and recolours the **alpha
  channel**. A solid background becomes a solid block in the menu bar.
- **Colour is fine for the app icon.** The icon composites the full-colour mark
  over the tile, so a multi-colour mark works; a dark mark on the dark tile can
  be low-contrast. If you need a different tile treatment, drop a custom
  `Resources/AppIcon-1024.png` in place (it will be used unless something newer
  regenerates it) or edit `scripts/make-icon.swift`.
- **Square-ish is best.** Non-square SVGs are letterboxed into the square canvas.
- **The menu bar shows the mark small** (18 pt). Fine detail disappears; a bold,
  simple silhouette reads best.

### How the app uses the logo at runtime

`Sources/Symplast/Support/BrandAssets.swift`:

- `BrandAssets.logo()` loads `AppLogo.png` from the bundle (`NSImage(named:)`,
  then the bundle URL).
- `BrandAssets.menuBarImage(height:tint:)` resizes it to 18 pt. With no tint it is
  a _template_ image (the system tints it); the red "needs attention" state passes
  a tint that is baked into the pixels.
- If the asset is missing (e.g. running the raw binary), `BrandLogo` falls back to
  the SF Symbol `arrow.triangle.2.circlepath`.

## 2. The app build

### Repository map

```
Package.swift                 SwiftPM manifest (executable Symplast + tests)
Sources/Symplast/             app sources
Tests/SymplastTests/          unit tests
Resources/Info.plist          bundle metadata (name, id, version)
Resources/AppLogo.png         generated mark (committed)
Resources/AppIcon-1024.png    generated icon (committed)
logo.svg                      brand source of truth
scripts/                      build, preview, packaging helpers
.github/workflows/            CI and release automation
```

### Swift package vs `.app`

`swift build` produces a bare executable, not a `.app`. A menu-bar app needs a
bundle (Info.plist, icon, embedded resources), which is what `build-app.sh`
assembles:

```sh
swift build            # compile only (fast) — no .app
swift test             # run unit tests
./scripts/build-app.sh # compile + assemble build/Symplast.app
```

### The two distribution shapes

Both come from the same source; the only difference is whether Mutagen is embedded.

|         | Bodyless (default)              | Self-contained                            |
| ------- | ------------------------------- | ----------------------------------------- |
| Build   | `./scripts/build-app.sh`        | `BUNDLE_MUTAGEN=1 ./scripts/build-app.sh` |
| Mutagen | user must install it            | bundled in the app                        |
| Size    | a few MB                        | larger (CLI + cross-platform agents)      |
| Use     | people who already have Mutagen | a no-setup install                        |

The app finds Mutagen in this order (`MutagenClient.resolveExecutable`): the
Settings override → the **bundled** copy → common system paths → the login shell.

### What "embedding Mutagen" actually copies

Mutagen is a single CLI binary **plus a separate agent bundle**. Both must go in
`Contents/Resources/`:

- `mutagen` — the CLI/daemon (universal arm64 + x86_64 via `lipo`).
- `mutagen-agents.tar.gz` — the cross-platform agents Mutagen installs onto
  remote SSH/Docker endpoints. Without it, remote sync fails.

`scripts/fetch-mutagen.sh` fetches **source**, not upstream release executables.
It verifies the source SHA-256 pinned in `scripts/mutagen-source.json`, uses
upstream's `--mode=release --sspl=false` build for both the CLI and agents,
and combines the two macOS CLI binaries with `lipo`. This avoids the SSPL
enhancements included in official Mutagen binaries since v0.17.

Install the exact Go version listed in that JSON file, plus Xcode Command Line
Tools and Python 3. The documented `scripts/mutagen-0.18.1.patch` removes only
the obsolete Windows ARM32 agent target no longer supported by Go 1.26. All
other upstream agent targets are included; macOS agents retain cgo/FSEvents.
Inherited Go build tags are cleared to prevent accidental SSPL builds.

```sh
bash scripts/fetch-mutagen.sh
BUNDLE_MUTAGEN=1 \
  MUTAGEN_BIN=build/mutagen/mutagen \
  MUTAGEN_AGENTS=build/mutagen/mutagen-agents.tar.gz \
  ./scripts/build-app.sh
```

### Install, release, and CI

```sh
./scripts/install.sh                    # build, copy to /Applications, launch
BUNDLE_MUTAGEN=1 ./scripts/install.sh   # self-contained install
```

```sh
bash scripts/package-release.sh         # both variants → dist/*.dmg
```

- `.github/workflows/ci.yml` — `swift build` + `swift test` on pushes and PRs.
- `.github/workflows/release.yml` — on `v*` tags: tests, builds non-SSPL Mutagen
  from pinned source, packages both universal DMGs, and creates a **draft** for
  review, not a public release. Signing and notarization configuration is kept
  in the local maintainer runbook, not the public README.

### Signing

For a Developer ID build, set `CODESIGN_IDENTITY` **before** running
`fetch-mutagen.sh`: it forwards `--macos-codesign-identity` to the upstream builder,
which signs the macOS remote agents **before** archiving them. `build-app.sh`
then signs the embedded universal `mutagen` binary first, then the app. Ad-hoc
(`-`) is the default and is fine locally. For distribution, set
`CODESIGN_IDENTITY` to a Developer ID; the script then adds the hardened runtime
and a secure timestamp, which notarization requires.

Release packaging sets `UNIVERSAL=1`, compiling the app for **arm64 and x86_64**
and verifying both slices. A universal Mutagen alone does not make the app universal.
Bundled builds require the agent archive; missing agents and signing failures
are fatal rather than silently shipping a broken app. Every app/DMG includes
Symplast's license and third-party notices; bundled releases also include
Mutagen's compiled legal text, source license, exact-version source/build links,
source checksum, Go version, and compatibility patch. Release packaging rejects
unverified/custom binaries and inspects both CLI slices and every archived
agent's Go metadata for the correct build tags and cgo configuration. Local
`build-app.sh` still accepts custom `MUTAGEN_BIN`/`MUTAGEN_AGENTS` paths; those
are not a substitute for the verified release source build.

Without Developer ID credentials, DMGs are ad-hoc signed and clearly labeled
**not notarized**. If a Developer ID identity is provided, packaging requires
notarization credentials, staples both apps and disk images, and computes
`SHA256SUMS` and `symplast.rb` only after all artifacts are finalized. See the
[installation guide](installation.md) for user-facing first-launch guidance.

The portable release-tool checks can be run separately from the macOS app:

```sh
python3 -m unittest discover -s tests-release -v
```

## 3. Recipes

**I changed my logo.**

```sh
cp my-mark.svg logo.svg
./scripts/build-app.sh && open build/Symplast.app
```

**I just want to see the UI with the current logo, without building the app.**

```sh
bash scripts/preview-ui.sh .report/preview       # writes PNGs to .report/preview
```

This compiles the sources standalone, loads `Resources/AppLogo.png`, and renders
light/dark fixtures. `--public` uses cleaner example data; `--native` captures the
real popover (needs screen-recording permission).

**The icon still looks old.** Delete the generated files and rebuild:

```sh
rm -f Resources/AppLogo.png Resources/AppIcon-1024.png && ./scripts/build-app.sh
```

## 4. Troubleshooting

| Symptom                                      | Cause / fix                                                                                       |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Menu bar shows a solid block                 | `logo.svg` has an opaque background. Make it transparent.                                         |
| Menu bar shows the circular-arrows SF Symbol | `AppLogo.png` is missing from the bundle — rebuild so it is copied in.                            |
| Curves/shapes look wrong                     | You are on an old checkout with the polygon-only parser; update to the current `make-logo.swift`. |
| Logo changes do nothing                      | `AppLogo.png` is newer than `logo.svg`; `rm` the generated PNGs and rebuild.                      |
| "Mutagen not found" in the panel             | Bodyless build without Mutagen installed. Install it or use a self-contained build.               |
| Remote sync fails in the self-contained app  | The build had no `mutagen-agents.tar.gz`; pass `MUTAGEN_AGENTS`.                                  |
| Bundled app is much larger                    | Expected: it embeds Mutagen's cross-platform agent bundle.                                        |
