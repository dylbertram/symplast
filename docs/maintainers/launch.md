# Launch checklist

## Decide first

1. **Public distribution:** a private GitHub repository's releases cannot be
   downloaded anonymously. Decide whether to make the repository public, and
   audit the entire Git history for credentials/private content first. Changing
   visibility is a separate, explicit approval.
2. **Gatekeeper:** paid Apple membership is required. Configure Developer ID
   signing/notarization before public release. Ad-hoc drafts are testing-only;
   Homebrew is not a bypass.
3. **Mutagen redistribution:** bundled releases build checksum-pinned source with
   `--mode=release --sspl=false` for both the CLI and agents; official SSPL
   release binaries are rejected. Retain legal/source/build notices and the
   compatibility patch. Read [`THIRD-PARTY-NOTICES.md`](../../THIRD-PARTY-NOTICES.md)
   before publishing.

## Prepare

- Review staged renames and uncommitted app changes before committing.
- Run `swift test` and `python3 -m unittest discover -s tests-release -v`.
- Install the exact Go version in `scripts/mutagen-source.json`, then run
  `bash scripts/fetch-mutagen.sh` and `VERSION=0.1.0 bash scripts/package-release.sh`.
  For notarized releases set `CODESIGN_IDENTITY` before **both** commands so
  archived macOS agents are signed too.
- Mount each DMG read-only, inspect the app and Applications shortcut, and test on
  both Intel and Apple Silicon Macs running macOS 14+. A local `open` is not a
  Gatekeeper test.
- Review `dist/SHA256SUMS`, `dist/symplast.rb`, and `dist/RELEASE-NOTES.md`.
- Commit the intended tracked source, scripts, docs, and workflows. Keep the
  local `release.env`, `.env*`, signing material, `build/`, and `dist/` out of Git.

## Publish

1. Configure [GitHub](README.md#repository-configuration). Enable Actions and
   create the environments.
2. Push the reviewed `main` branch. Create and push `v0.1.0`; the workflow builds
   a draft.
3. Inspect the draft artifacts and warning text. Publish the draft **manually**
   only after downloads can be publicly accessed. Never replace a published DMG
   under the same version; its Homebrew checksum would change.
4. Configure [Homebrew](homebrew.md); test the public cask, then enable its site
   CTA.
5. Configure the [website](website.md); deploy and attach the domain.
6. Verify HTTPS, rendering, the DMG download, checksums, the Homebrew install, and
   first-launch guidance as an unauthenticated user.
7. Update the README's release/tap status language when complete.

If the website goes live before the release, it intentionally shows **Coming
soon**. Publishing a stable release triggers a site rebuild; after enabling
Homebrew, manually rerun **Publish website** so its install command appears.
