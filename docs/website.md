# Website development

The `symplast.app` website uses Svelte 5, SvelteKit, Tailwind CSS 4, and Bits UI.
SvelteKit prerenders both pages with the static adapter. Cloudflare Pages still
serves only `dist/site/`; no server or browser-side GitHub API calls are required.

## Local preview

Install dependencies with Node.js 24+ and prepare the public assets:

```sh
npm ci --prefix site
python3 scripts/build-site.py --prepare-only
npm run dev --prefix site
```

Vite prints the preview URL and updates the page as you edit. Components live in
`site/src/`, Tailwind theme tokens in `site/src/app.css`, and hosting files in
`site/static/`. Icons and the copy command are reusable Svelte components; the
copy tooltip uses Bits UI. Screenshot assets are copied from the repository.

## Production build

```sh
python3 scripts/build-site.py
npm run check --prefix site
python3 scripts/verify-site.py
python3 -m http.server 8080 --directory dist/site
```

Without published release metadata, downloads display **Coming soon**. To
preview a published release, pass `--release-metadata path/to/release.json` to
the Python preparation/build command, and optionally `--homebrew-ready`. The
metadata must describe a non-draft, non-prerelease `vX.Y.Z` release with both
DMGs and `SHA256SUMS` at their exact GitHub download URLs. Only validated public
fields are passed into Svelte; the release body and other metadata are not shipped.

Generated assets and release data are gitignored. Never place credentials or
private files in `site/static/`. The build rejects unexpected public files.

`.github/workflows/pages.yml` installs dependencies, builds and verifies the
static output, and deploys on main-branch site changes, published releases, or
manual runs. SvelteKit generates CSP hashes for hydration scripts; the hosting
headers separately prevent framing. Pull requests do not receive deployment
credentials.
