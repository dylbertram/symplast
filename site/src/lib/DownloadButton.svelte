<script>
  import Icon from './Icon.svelte';
  /** @type {{ href: string }} */
  let { href } = $props();
</script>

<a class="inline-flex items-center justify-center gap-2.5 rounded-md border border-ink bg-ink px-5 py-3 text-sm font-medium text-page no-underline hover:border-accent hover:bg-accent hover:no-underline" {href}>
  <Icon name="download" /><span>Download for macOS</span>
</a>
