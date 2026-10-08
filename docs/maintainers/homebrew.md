# Homebrew cask

Symplast is a GUI app, so it is distributed as a **cask**, not a CLI formula. The
cask installs the self-contained universal DMG and requires macOS 14+. A custom
tap does not require admission to Homebrew's official cask repository or Apple
membership, but Gatekeeper warnings still apply to non-notarized builds.

## One-time activation

1. Create a **public** repository `<owner>/homebrew-symplast`, initialize its
   default branch, and add a README/license. Keep it separate from the app repo.
2. Create a fine-grained GitHub PAT with Contents read/write for **only** that
   tap. Add it as `HOMEBREW_TAP_TOKEN` in this repository's **homebrew**
   environment.
3. Set repository variable `HOMEBREW_TAP=<owner>/homebrew-symplast`.
4. Publish a reviewed, stable, **public** app release, or manually run **Publish
   Homebrew cask** with its tag (e.g. `v0.1.0`). A private app repository cannot
   serve the cask's anonymous download URL.
5. The workflow downloads the bundled DMG, checksum list, and generated cask,
   verifies them, regenerates the cask to compare its exact hash/signing notice,
   and commits `Casks/symplast.rb` to the tap. No placeholder SHA or quarantine
   bypass is used. Late reruns cannot downgrade the latest stable release.
6. On a clean Mac with Homebrew:

```sh
brew install --cask <owner>/symplast/symplast
brew info --cask symplast
brew audit --cask --online symplast
brew style --cask symplast
```

Test first launch with normal quarantine in place. Then set `HOMEBREW_READY=true`
and rerun **Publish website** to expose the install command.

## Manual cask updates

For the exact DMG downloaded from a published release:

```sh
python3 scripts/generate-cask.py 0.1.0 dist/Symplast-0.1.0-bundled.dmg --output dist/symplast.rb
```

Use `--notarized` **only** for an actually notarized artifact. Copy that cask to
the tap's `Casks/` directory, review its hash, commit, and push. A local build's
hash is not interchangeable with the GitHub-built DMG. Never replace an image
under an existing tag; release a new version instead.

Standard uninstall preserves preferences and all Mutagen data. Optional `--zap`
removes Symplast preferences and saved definitions only. The cask must never
delete `~/.mutagen`, terminate the daemon, or disable Gatekeeper.
