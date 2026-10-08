<script>
  import '../app.css';
  import { Tooltip } from 'bits-ui';
  /** @type {{ children: import('svelte').Snippet }} */
  let { children } = $props();
</script>

<a class="fixed -top-24 left-5 z-10 rounded bg-surface px-4 py-2 focus:top-3" href="#main">Skip to content</a>
<Tooltip.Provider delayDuration={200}>
  {@render children()}
</Tooltip.Provider>
