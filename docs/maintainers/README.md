# Maintainer guide

Operator documentation for building, signing, and publishing Symplast. This is
the sanitized copy that lives in the repository; account-specific values are
shown as placeholders (`<owner>`, `<TEAMID>`, `you@example.com`). Never add real
credentials, Apple account identifiers, or API tokens here — those belong in
GitHub environment secrets or a local, git-ignored file.

Symplast is an independent project, not affiliated with Mutagen or Docker, Inc.
User-facing documentation lives in [`docs/`](../); this folder is for maintainers.

## Contents

- [Signing and notarization](signing.md)
- [Website (Cloudflare Pages)](website.md)
- [Homebrew cask](homebrew.md)
- [Launch checklist](launch.md)
- [Local signing template](release.env.example) — copy to a git-ignored `release.env` in the repository root

## Repository configuration

- Default branch `main`, protected: require a pull request, required status
  checks **`build`** and **`release-tools`** (strict), linear history, no
  force-push or deletion, conversation resolution, enforced for admins.
- Release tags `v*` are protected against deletion, update, and non-fast-forward.
- Environments and their deployment branch policies:

  | Environment | Allowed ref | Purpose |
  | --- | --- | --- |
  | `release` | tag `v*` | signing + notarization credentials |
  | `website` | branch `main` | Cloudflare Pages deploy |
  | `homebrew` | branch `main`, tag `v*` | tap update |

- `.github/CODEOWNERS` covers `.github/` and `scripts/` so review is requested
  for workflow and release-tooling changes.
- The `release` workflow refuses a tag that is not contained in protected `main`.

## Variables (repository scope)

| Name | Effect |
| --- | --- |
| `PAGES_ENABLED` | `true` only after the Cloudflare project and secrets exist |
| `HOMEBREW_TAP` | `<owner>/homebrew-symplast`; empty disables cask publication |
| `HOMEBREW_READY` | `true` only after the public install command has been tested |

These must be repository variables, not environment-only, because job
eligibility is evaluated before an environment is entered.

## Secrets (environment scope)

- **`website`**: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`
- **`homebrew`**: `HOMEBREW_TAP_TOKEN` (fine-grained PAT, Contents read/write for
  the tap repository only — the built-in token cannot write another repo)
- **`release`**: see [signing.md](signing.md)

Set them with GitHub's UI or interactive `gh secret set NAME --env ENV`. Never
put secret values in workflow YAML, README, git remote URLs, or command examples.

## Releasing

After reviewing and committing all intended files:

```sh
git tag -a v0.1.0 -m "Symplast 0.1.0"
git push origin v0.1.0
```

**Release** runs tests, checks out that exact tag, installs the pinned Go
version, builds checksum-pinned non-SSPL Mutagen source and all supported agents,
builds universal apps, signs them, notarizes/staples them (unless explicitly
testing ad-hoc), creates DMGs, and hashes the **final** images. It attaches both
DMGs, `SHA256SUMS`, and `symplast.rb` to a **draft** GitHub release. A manual run
accepts `version=0.1.0`, but that tag must already exist; existing releases are
never overwritten.

Publish the reviewed draft in GitHub's UI. That human `release.published` event
triggers the Homebrew and website workflows. Actions-created events using the
built-in token normally do not cascade, which is another reason publication is
manual.

## Rollback

Do not overwrite tagged artifacts. Publish a new corrective version. To remove a
broken latest release, mark it as a prerelease/unpublish it as appropriate, then
rerun website deployment and update the tap to a reviewed working version. The
tap workflow rejects accidental older-version reruns.
