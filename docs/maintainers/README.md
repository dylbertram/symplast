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
  The check compares ancestry, not content: a cherry-picked or rebased copy of
  the same work on another branch is rejected even when the trees are
  byte-identical.

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

After reviewing and committing all intended files, tag the release commit **on
`main`**. Never tag a work-branch commit — `dev` or topic branches often carry
cherry-picked or rebased copies of the same changes, and the workflow's
containment check rejects them with `Refusing to release vX.Y.Z: not contained
in the protected main branch (compare status: diverged)` even when the content
matches `main` exactly.

Before pushing, create the tag locally and confirm its commit is already
reachable from `main` — the push must not run if the check fails:

```sh
git tag -a v0.2.0 -m "Symplast 0.2.0"
git merge-base --is-ancestor v0.2.0^{commit} origin/main && echo "ok: tag is in main"
git push origin v0.2.0
```

If the check fails, delete the local tag with `git tag -d v0.2.0`, re-create it
on the `main` release commit, and only then push. Never push a tag that points
outside `main`.

**Release** runs tests, checks out that exact tag, installs the pinned Go
version, builds checksum-pinned non-SSPL Mutagen source and all supported agents,
builds universal apps, signs them, notarizes/staples them (unless explicitly
testing ad-hoc), creates DMGs, and hashes the **final** images. It attaches both
DMGs, `SHA256SUMS`, and `symplast.rb` to a **draft** GitHub release. A manual run
accepts `version=0.2.0`, but that tag must already exist; existing releases are
never overwritten.

Publish the reviewed draft in GitHub's UI. That human `release.published` event
triggers the Homebrew and website workflows. Actions-created events using the
built-in token normally do not cascade, which is another reason publication is
manual.

## Fixing a mistagged tag

The **Protect release tags** ruleset rejects deleting, updating, or
force-moving `v*` tags. If a tag was pushed for a commit outside `main` and **no
release has been created from it yet**, an admin must temporarily relax the
ruleset, move the tag, and immediately restore the ruleset:

```sh
git push origin :refs/tags/v0.2.0
git tag -d v0.2.0
git tag -a v0.2.0 <the main release commit> -m "Symplast 0.2.0"
git push origin v0.2.0
```

Once a GitHub release exists for a tag, never move that tag — publish a new
version instead. Keep long-lived branches rebased onto (or merged with) `main`
so parallel cherry-picked copies of release work cannot accumulate.

## Troubleshooting a release

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Refusing to release vX.Y.Z: not contained in the protected main branch (compare status: diverged)` | The tag points outside `main`, usually at cherry-picked copies of the same work | Move the tag to the `main` commit as in [Fixing a mistagged tag](#fixing-a-mistagged-tag) |
| `GH013: Repository rule violations … Cannot delete this tag` | The **Protect release tags** ruleset blocks tag moves | Have an admin temporarily relax the ruleset, then restore it |
| **Publish Homebrew cask** fails with `gh: Not Found (HTTP 404)` | It was dispatched before a release existed for that tag | Publish the draft release first; `release.published` runs the workflow automatically |
| `Only the latest stable release may update the tap` | The tag is not the newest published stable release | Intended; only the latest release updates the tap |
| **Release** fails at "Refuse to overwrite an existing release" on a rerun | A release for that tag already exists | Never reuse the tag; publish a new corrective version |

## Rollback

Do not overwrite tagged artifacts. Publish a new corrective version. To remove a
broken latest release, mark it as a prerelease/unpublish it as appropriate, then
rerun website deployment and update the tap to a reviewed working version. The
tap workflow rejects accidental older-version reruns.
