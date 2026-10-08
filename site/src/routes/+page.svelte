<script>
  import Icon from '$lib/Icon.svelte';
  import DownloadButton from '$lib/DownloadButton.svelte';
  import CopyCommand from '$lib/CopyCommand.svelte';
  import Footer from '$lib/Footer.svelte';
  /** @type {{ data: import('./$types').PageData }} */
  let { data } = $props();
</script>

<svelte:head>
  <title>Symplast — folder sync, a click away</title>
  <meta name="description" content="Folder sync, a click away. Manage Mutagen sessions from your Mac’s menu bar with live status, simple controls, and saved sessions." />
  <meta property="og:title" content="Symplast — folder sync, a click away" />
  <meta property="og:description" content="Check sync status, pause or resume, and manage saved sessions from your Mac’s menu bar. A native macOS companion for Mutagen." />
  <meta property="og:type" content="website" />
  <meta property="og:url" content="https://symplast.app/" />
  <meta property="og:image" content="https://symplast.app/assets/app-icon.png" />
  <link rel="canonical" href="https://symplast.app/" />
</svelte:head>

<header class="wrap flex items-center justify-between border-b border-line py-[22px] md:py-[30px]">
  <a class="brand" href="/" aria-label="Symplast home"><img class="object-contain brightness-0 opacity-85 dark:brightness-100 dark:opacity-100" src="/assets/mark.png" width="30" height="30" alt="" />Symplast</a>
  <nav class="flex gap-[18px] text-xs md:gap-[34px] md:text-sm" aria-label="Main navigation"><a class="no-underline" href="#features">Features</a><a class="no-underline" href="#downloads">Get the app <span aria-hidden="true">↗</span></a></nav>
</header>
<main id="main">
  <section class="wrap grid items-center gap-10 py-[54px] md:grid-cols-[minmax(0,1.2fr)_minmax(0,1fr)] md:gap-8 md:py-16 lg:gap-16 lg:pt-[88px] lg:pb-[92px]" aria-labelledby="hero-title">
    <div>
      <p class="eyebrow"><span class="mr-2 inline-block size-[7px] rounded-full bg-accent ring-4 ring-accent/10" aria-hidden="true"></span>Sync from your menu bar</p>
      <h1 id="hero-title">Folder sync.<br /><span class="text-accent">A click away.</span></h1>
      <p class="my-[26px] max-w-[450px] text-base leading-[1.7] text-muted md:text-[17px]">Keep local and remote folders in sync with <a href="https://mutagen.io/">Mutagen</a>, managed from your Mac’s menu bar. No terminal required.</p>
      <div class="flex flex-wrap items-center gap-5"><DownloadButton href={data.release.download} /><a class="text-link inline-flex items-center gap-2" href="https://github.com/dylbertram/symplast"><Icon name="github" /><span>View on GitHub</span></a></div>
      <p class="mt-5 text-[11px] text-muted">macOS 14+ <span class="mx-1">·</span> Apple Silicon &amp; Intel <span class="mx-1">·</span> Free &amp; open source</p>
    </div>
    <figure class="m-0 w-full max-w-[430px] justify-self-center p-[22px] md:max-w-none md:p-[18px] lg:px-7 lg:py-6">
      <picture class="block overflow-hidden rounded-[11px] shadow-[0_24px_60px_-16px_#00000030,0_2px_8px_#0000000d,0_0_0_1px_#80808018]">
        <source media="(prefers-color-scheme: dark)" srcset="/assets/sessions-dark.png" />
        <img class="block h-auto w-full saturate-[.8]" src="/assets/sessions-light.png" width="792" height="740" alt="The Symplast menu-bar panel showing a connected folder, a remote needing attention, and a saved session." />
      </picture>
    </figure>
  </section>
  <section class="section wrap" id="features" aria-labelledby="sync-title">
    <h2 id="sync-title">Local files.<br />Ready wherever you work.</h2>
    <p class="mt-6 max-w-[720px] text-base text-muted"><a href="https://mutagen.io/">Mutagen</a> keeps two folders in sync by detecting changes and transferring them between your Mac and another folder or SSH server. Symplast gives you a native interface to create and manage those sessions; Mutagen does the syncing.</p>
    <div class="feature-grid">
      <article><h3>Edit here. Build there.</h3><p class="feature-copy">Keep a project on your Mac for your editor and local tools, while a copy on your server stays up to date for remote builds or testing. Choose two-way sync, or send changes in one direction.</p></article>
      <article><h3>Copies, not shortcuts.</h3><p class="feature-copy">A shortcut or symlink points to existing files; it doesn’t keep a second folder up to date. Sync gives each location its own files, even when they’re on different machines.</p></article>
      <article><h3>No network drive required.</h3><p class="feature-copy">A mounted network drive accesses remote files over the connection. With sync, your tools work on local files. Keep editing when disconnected; Mutagen synchronizes changes when the connection returns.</p></article>
    </div>
  </section>
  <section class="section wrap grid grid-cols-1 gap-[26px] md:grid-cols-2 md:gap-9 lg:gap-16" id="downloads" aria-labelledby="downloads-title">
    <div><p class="eyebrow">Download or use Homebrew</p><h2 id="downloads-title">Get Symplast<br />for your Mac.</h2><p class="mt-6 text-sm text-muted">No account, no subscription. The recommended download includes Mutagen, so there’s nothing else to install.</p></div>
    <div class="min-w-0 rounded-[10px] border border-line bg-surface">
      <div class="install-option">
        {#if data.release.available}
          <h3 class="mb-3 flex items-center gap-2.5"><Icon name="mac" class="size-[22px] text-accent" /><span>Direct download</span></h3>
          <DownloadButton href={data.release.download} />
          <p class="mt-2.5 text-[13px] text-muted">Recommended easy install · Includes Mutagen<br />Version {data.release.version} · Apple Silicon &amp; Intel</p>
          {#if !data.release.notarized}<p class="mt-2.5 text-[13px] text-muted"><strong>This build is not notarized by Apple.</strong> macOS may block first launch. See the <a href="https://github.com/dylbertram/symplast/blob/main/docs/installation.md">installation guide</a> before opening it. Never disable Gatekeeper or bypass a malware or damaged-app warning.</p>{/if}
          <a class="secondary-download" href={data.release.app_only_download}><Icon name="download" /><span>Download app only (without Mutagen)</span></a>
          <p class="mt-2.5 text-[13px] text-muted">Already use Mutagen? Choose the smaller app-only download and keep your existing installation.</p>
          <a class="secondary-download" href={data.release.notes}>Checksums &amp; release notes ↗</a>
        {:else}
          <h3 class="mb-3">Coming soon for macOS.</h3><p class="text-[13px] text-muted">The first public release is being prepared. Downloads will appear here when they’re ready.</p><a class="secondary-download" href="https://github.com/dylbertram/symplast">Follow the project on GitHub ↗</a>
        {/if}
      </div>
      <div class="install-option border-t border-line">
        <h3 class="mb-3 flex items-center gap-2.5"><Icon name="terminal" class="size-[22px] text-accent" /><span>Install with Homebrew</span></h3>
        {#if data.release.homebrew_ready}<CopyCommand /><p class="mt-2.5 text-[13px] text-muted">Installs the self-contained app from our public tap.</p>{:else}<p class="text-[13px] text-muted">The Homebrew tap is being prepared alongside the first release.</p>{/if}
      </div>
    </div>
  </section>
  <section class="section wrap grid grid-cols-1 gap-[26px] md:grid-cols-2 md:gap-9 lg:gap-16" aria-labelledby="installation-title">
    <div><p class="eyebrow">From install to sync</p><h2 id="installation-title">Start with<br />your folders.</h2></div>
    <div><p class="mb-4 text-sm leading-[1.8] text-muted">Open Symplast from Applications or Spotlight, then click its menu bar icon to create a session. Choose a local folder and a destination, set your sync options, and start syncing.</p><p class="mb-4 text-sm leading-[1.8] text-muted">Syncing to an SSH server? You’ll need a working SSH key and agent; Symplast cannot prompt for a password or key passphrase. Your Mutagen sessions keep running even when you quit Symplast.</p><a class="text-link" href="https://github.com/dylbertram/symplast/blob/main/docs/usage.md">Simple usage guide ↗</a><br /><a class="text-link" href="https://github.com/dylbertram/symplast/blob/main/docs/installation.md">Installation &amp; troubleshooting ↗</a></div>
  </section>
</main>
<Footer />
