<script>
  import { page } from '$app/stores';
  import { docsModules, findDocModule } from '$lib/docs/modules.js';

  $: currentSlug = $page.params.slug ?? '';
  $: currentModule = findDocModule(currentSlug) ?? docsModules[0];
</script>

<svelte:head>
  <title>Documentación — Flow Connected</title>
</svelte:head>

<div class="docs-shell">
  <header class="docs-topbar">
    <span class="docs-topbar-icon">📖</span>
    <div class="docs-topbar-text">
      <span class="docs-topbar-title">Documentación</span>
      <span class="docs-topbar-sub">Flow Connected</span>
    </div>
  </header>

  <div class="docs-body">
    <nav class="docs-nav" aria-label="Módulos de la documentación">
      {#each docsModules as m}
        <a
          href={m.slug ? `/docs/${m.slug}` : '/docs'}
          class="docs-nav-item"
          class:active={m.slug === currentSlug}
        >
          <span class="docs-nav-icon">{m.icon}</span>
          <span class="docs-nav-label">{m.title}</span>
        </a>
      {/each}
    </nav>

    <main class="docs-content">
      <slot />
    </main>

    {#if currentModule?.sections?.length}
      <aside class="docs-toc" aria-label="En esta página">
        <span class="docs-toc-label">En esta página</span>
        <nav class="docs-toc-nav">
          {#each currentModule.sections as s}
            <a href="#{s.id}">{s.title}</a>
          {/each}
        </nav>
      </aside>
    {/if}
  </div>
</div>

<style>
.docs-shell {
  display: flex;
  flex-direction: column;
  min-height: 100vh;
  background: var(--bg);
}

.docs-topbar {
  display: flex;
  align-items: center;
  gap: 12px;
  height: 60px;
  flex-shrink: 0;
  padding: 0 24px;
  background: var(--primary-dark);
  color: #fff;
  position: sticky;
  top: 0;
  z-index: 10;
}
.docs-topbar-icon { font-size: 1.375rem; }
.docs-topbar-text { display: flex; flex-direction: column; line-height: 1.15; }
.docs-topbar-title { font-size: .9375rem; font-weight: 700; letter-spacing: .04em; text-transform: uppercase; }
.docs-topbar-sub { font-size: .75rem; color: rgba(255,255,255,.7); }

.docs-body {
  flex: 1;
  display: flex;
  align-items: flex-start;
}

/* Left nav */
.docs-nav {
  width: 240px;
  flex-shrink: 0;
  position: sticky;
  top: 60px;
  height: calc(100vh - 60px);
  overflow-y: auto;
  padding: 20px 12px;
  background: var(--surface);
  border-right: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.docs-nav-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px 12px;
  border-radius: var(--radius-sm);
  font-size: .875rem;
  font-weight: 500;
  color: var(--text-muted);
  text-decoration: none;
  transition: background var(--transition), color var(--transition);
}
.docs-nav-item:hover { background: var(--sidebar-hover); color: var(--primary); }
.docs-nav-item.active { background: var(--primary-light); color: var(--primary-dark); font-weight: 600; }
.docs-nav-icon { font-size: 1.05rem; width: 20px; text-align: center; flex-shrink: 0; }

/* Content */
.docs-content {
  flex: 1;
  min-width: 0;
  padding: 40px 48px;
  max-width: 860px;
}

/* Right TOC rail */
.docs-toc {
  width: 220px;
  flex-shrink: 0;
  position: sticky;
  top: 60px;
  height: calc(100vh - 60px);
  overflow-y: auto;
  padding: 40px 24px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.docs-toc-label {
  font-size: .72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .06em;
  color: var(--text-muted);
}
.docs-toc-nav { display: flex; flex-direction: column; gap: 8px; }
.docs-toc-nav a {
  font-size: .8125rem;
  color: var(--text-muted);
  text-decoration: none;
}
.docs-toc-nav a:hover { color: var(--primary); text-decoration: none; }

@media (max-width: 1100px) {
  .docs-toc { display: none; }
}
@media (max-width: 768px) {
  .docs-nav { display: none; }
  .docs-content { padding: 24px 20px; }
}
</style>
