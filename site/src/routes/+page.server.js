import release from '$lib/generated/release.json';

export function load() {
  // The site has no coming-soon state: it always links the published release.
  // A build without real release data fails here instead of shipping a page
  // with dead download links.
  if (!release.available || !release.download || !release.app_only_download || !release.notes) {
    throw new Error('Missing published release data; generate it with scripts/build-site.py.');
  }
  return {
    release: {
      version: release.version,
      download: release.download,
      app_only_download: release.app_only_download,
      notes: release.notes,
      notarized: release.notarized,
      homebrew_ready: release.homebrew_ready
    }
  };
}
