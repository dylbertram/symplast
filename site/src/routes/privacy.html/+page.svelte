<script>
  import Footer from '$lib/Footer.svelte';
</script>

<svelte:head>
  <title>Privacy — Symplast</title>
  <meta name="description" content="How Symplast and its website handle your information." />
  <link rel="canonical" href="https://symplast.app/privacy.html" />
</svelte:head>

<header class="wrap flex items-center justify-between border-b border-line py-[30px]"><a class="brand" href="/">Symplast</a><a class="text-link" href="/">Back to home</a></header>
<main class="wrap max-w-[720px] py-16" id="main">
  <p class="eyebrow">Your folders stay yours</p><h1 class="mb-8 text-5xl">Privacy, simply.</h1>
  <h2 class="mt-8 text-2xl">The app</h2>
  <p class="mt-4 text-muted">Symplast has no accounts, advertising, or analytics. It stores settings and saved session definitions locally on your Mac. It invokes Mutagen to synchronize the endpoints you configure, using your system’s SSH client for SSH targets. Folder paths, SSH usernames, and hostnames are part of those local definitions.</p>
  <p class="mt-4 text-muted">At launch, and when you manually check for updates, Symplast requests the public latest-release metadata from GitHub. The request contains no session, folder, or account information. GitHub receives normal connection metadata such as your IP address; see <a href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement">GitHub’s privacy statement</a>.</p>
  <p class="mt-4 text-muted">Symplast does not run a service that receives your synchronized files. Mutagen connects directly to your configured targets; their privacy and access policies still apply. Your SSH configuration, agent, Mutagen state, and local macOS preferences remain on your machine.</p>
  <h2 class="mt-8 text-2xl">This website</h2>
  <p class="mt-4 text-muted">This is a static site hosted by Cloudflare Pages. It uses no analytics scripts, tracking cookies, third-party fonts, or browser-side release API calls. Cloudflare processes normal web request information to deliver and protect the site; see <a href="https://www.cloudflare.com/privacypolicy/">Cloudflare’s privacy policy</a>.</p>
  <p class="mt-4 text-muted">Downloads and source links take you to GitHub, whose <a href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement">privacy policy</a> applies there.</p>
  <h2 class="mt-8 text-2xl">Questions</h2>
  <p class="mt-4 text-muted">Review the <a href="https://github.com/dylbertram/symplast">source code</a> or open an issue in the project repository.</p>
</main>
<Footer />
