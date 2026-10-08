<script>
  import Icon from './Icon.svelte';
  /** @type {{ href: string | null }} */
  let { href } = $props();
</script>

<a class="inline-flex items-center justify-center gap-2.5 rounded-md border border-ink bg-ink px-5 py-3 text-sm font-medium text-page no-underline hover:border-accent hover:bg-accent hover:no-underline" href={href || '#downloads'}>
  {#if href}<Icon name="download" /><span>Download for macOS</span>{:else}<span>Coming soon</span><span aria-hidden="true">↘</span>{/if}
</a>
