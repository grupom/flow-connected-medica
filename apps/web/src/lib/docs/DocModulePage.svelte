<script>
  // Renders one docs module's placeholder content. Shared by
  // routes/docs/+page.svelte (Introducción) and routes/docs/[slug]/+page.svelte
  // so both stay driven by the same `docsModules` config.
  export let mod;
</script>

<article class="doc-page">
  <h1><span class="doc-icon">{mod.icon}</span> {mod.title}</h1>

  {#each mod.sections as s}
    <section>
      <h2 id={s.id}>{s.title}</h2>
      <p class="placeholder">Contenido en construcción — próximamente.</p>
    </section>
  {/each}
</article>

<style>
.doc-page {
  display: flex;
  flex-direction: column;
  gap: 32px;
}
.doc-page h1 {
  display: flex;
  align-items: center;
  gap: 12px;
}
.doc-icon { font-size: 1.5rem; }

section {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
section h2 {
  scroll-margin-top: 76px;
}
.placeholder {
  color: var(--text-xs);
  font-style: italic;
}
</style>
