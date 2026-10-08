<script>
  import { onMount } from 'svelte';
  import Icon from './Icon.svelte';
  import { Tooltip } from 'bits-ui';
  const command = 'brew install --cask dylbertram/symplast/symplast';
  let canCopy = $state(false);
  let status = $state('');
  onMount(() => { canCopy = !!navigator.clipboard?.writeText; });
  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      status = 'Copied!';
    } catch {
      status = 'Could not copy. Select the command and copy it manually.';
    }
  }
</script>

<div class="flex min-w-0 items-center gap-1 rounded-md bg-tile p-1">
  <code class="min-w-0 flex-1 p-2 font-mono text-[11px] leading-relaxed whitespace-normal [overflow-wrap:anywhere]">{command}</code>
  {#if canCopy}
    <div class="relative shrink-0">
      <Tooltip.Root>
        <Tooltip.Trigger class="grid size-11 cursor-pointer place-items-center rounded-md border border-line bg-surface text-ink hover:border-accent hover:text-accent" type="button" aria-label="Copy Homebrew command" onclick={copy}><Icon name="copy" /></Tooltip.Trigger>
        <Tooltip.ContentStatic class="absolute right-0 bottom-full z-10 mb-2 w-max rounded-md border border-line bg-surface px-3 py-2 text-xs shadow-lg">Copy command</Tooltip.ContentStatic>
      </Tooltip.Root>
    </div>
  {/if}
</div>
<p class="mt-2 text-[13px] text-muted empty:hidden" role="status">{status}</p>
