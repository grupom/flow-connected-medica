<script>
  import { page } from '$app/stores';
  import DocModulePage from '$lib/docs/DocModulePage.svelte';
  import { findDocModule } from '$lib/docs/modules.js';

  $: mod = findDocModule($page.params.slug);
</script>

{#if mod}
  <DocModulePage {mod} />
{:else}
  <p>Página no encontrada.</p>
{/if}
