# Website (Cloudflare Pages)

The site is a **Direct Upload Pages** project, published by GitHub Actions. No
database, Workers function, or framework is needed. Only `dist/site/` is
uploaded; do not use the repository root as the deployment directory.

## One-time setup

1. Sign in to the intended Cloudflare account. Ensure the site's domain is a zone
   in that account with DNS managed by Cloudflare. Do not alter unrelated records.
2. In **Workers & Pages**, create a **Pages / Direct Upload** project named
   **symplast** with production branch **main**. Choose Direct Upload rather than
   Git integration because `.github/workflows/pages.yml` publishes it (Cloudflare
   cannot switch project types later).
3. Create a scoped API token: **Account → Cloudflare Pages → Edit**, limited to
   this account. No Global API Key, zone-wide DNS token, or registrar access is
   needed. Set an expiry and rotation reminder.
4. Put `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` in the GitHub
   **website** environment. Never commit their values.
5. Set repository variable `PAGES_ENABLED=true`. Run **Publish website** from
   `main` and verify the `*.pages.dev` deployment.
6. In the Pages project → **Custom domains**, add the apex domain and follow the
   Pages association process before editing DNS. Wait until DNS and TLS are
   **Active**. `.app` domains are HTTPS-only via HSTS preload.
7. Optionally add `www` and redirect it to the apex.

## Local/manual deployment

```sh
python3 scripts/build-site.py
npx wrangler@4 login
npx wrangler@4 pages project create symplast --production-branch=main
npx wrangler@4 pages deploy dist/site --project-name=symplast --branch=main
```

Skip project creation if it exists. OAuth login grants local access; the GitHub
workflow still needs its scoped token. Never paste the token into commands or
share session cookies.

## Automation behavior

- Main-branch site/asset changes, human-published releases, and manual runs build
  and deploy production. Pull requests only validate via CI; fork PRs get no
  secrets.
- The workflow always checks out **main**, even when triggered by a release tag.
- A private repository or missing published release produces a **Coming soon**
  site. Public stable releases supply the exact versioned bundled-DMG link.
- Set `HOMEBREW_READY=true` only after the tap works, then manually redeploy.
- `_headers` adds a no-script CSP and baseline security headers.

## Before declaring launch complete

- HTTPS certificate valid; apex and any `www` redirect work.
- Mobile and desktop layouts, dark mode, keyboard focus, and the Privacy page work.
- No hidden files, local secret files, environment values, or private screenshots in
  uploaded assets (the builder has an explicit allowlist).
- Download works in an incognito browser and matches `SHA256SUMS`.
- Site Gatekeeper text agrees with the release's actual notarization state.
- Retain prior Pages deployments for rollback; disable `PAGES_ENABLED` to stop
  automation.

Reference: https://developers.cloudflare.com/pages/how-to/use-direct-upload-with-continuous-integration/
