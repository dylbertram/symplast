<script>
  /** @type {{ name: 'download' | 'mac' | 'terminal' | 'copy' | 'github', class?: string }} */
  let { name, class: className = 'size-[18px]' } = $props();
</script>

<svg class="shrink-0 {className}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">
  {#if name === 'download'}
    <path d="M12 3v12m-5-5 5 5 5-5M4 15v5h16v-5" />
  {:else if name === 'mac'}
    <rect x="3" y="3" width="18" height="13" rx="2" /><path d="M8 21h8m-4-5v5" />
  {:else if name === 'terminal'}
    <rect x="3" y="3" width="18" height="18" rx="2" /><path d="m7 8 4 4-4 4m6 0h4" />
  {:else if name === 'github'}
    <path fill="currentColor" stroke="none" d="M12 .297C5.37.297 0 5.67 0 12.297c0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.043-1.61-4.043-1.61-.546-1.387-1.333-1.756-1.333-1.756-1.09-.745.083-.729.083-.729 1.205.084 1.838 1.237 1.838 1.237 1.07 1.835 2.807 1.305 3.492.998.108-.776.418-1.305.762-1.605-2.665-.3-5.466-1.333-5.466-5.93 0-1.31.467-2.38 1.235-3.22-.123-.303-.535-1.523.117-3.176 0 0 1.008-.322 3.301 1.23A11.52 11.52 0 0 1 12 6.1c1.02.005 2.045.138 3.003.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.873.119 3.176.77.84 1.233 1.91 1.233 3.22 0 4.61-2.805 5.625-5.475 5.921.43.372.823 1.102.823 2.222 0 1.606-.015 2.898-.015 3.292 0 .322.216.694.825.576C20.565 22.095 24 17.598 24 12.297 24 5.67 18.627.297 12 .297Z" />
  {:else}
    <rect x="8" y="8" width="13" height="13" rx="2" /><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3" />
  {/if}
</svg>
