# Website development

The `symplast.app` website is plain HTML and CSS. It has no framework,
JavaScript, analytics, external fonts, or runtime dependencies. Cloudflare Pages
serves only the generated `dist/site/` directory, never the repository itself.

```sh
python3 scripts/build-site.py
python3 -m http.server 8080 --directory dist/site
```

Open `http://localhost:8080`. Source files live in `site/`; screenshots and brand
assets are copied from their existing repository locations when the site builds.

Without published release metadata the page displays **Coming soon**, not a
broken DMG link. To preview the download state, pass a JSON file shaped like a
GitHub release to `--release-metadata`. It must be a non-draft, non-prerelease
`vX.Y.Z` release with a bundled DMG and `SHA256SUMS` asset. The exact expected
GitHub download URL is validated before it is used. `--homebrew-ready` enables
the install command only when a release is also available.

`.github/workflows/pages.yml` builds and deploys on main-branch site changes,
published releases, or manual runs. Pull requests validate the site but do not
receive deployment credentials. Deployment configuration and account setup
are intentionally kept in the maintainer's local runbook.
