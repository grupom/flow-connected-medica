<script>
  import { createEventDispatcher } from 'svelte';

  export let icon = '';
  export let title = '';
  export let subtitle = '';
  export let saving = false;

  const dispatch = createEventDispatcher();
</script>

<div class="config-section">
  <div class="config-header">
    <span class="config-icon">{icon}</span>
    <div>
      <h3 class="config-title">{title}</h3>
      <p class="config-sub">{subtitle}</p>
    </div>
  </div>

  <div class="config-body">
    <slot />

    <div class="config-input-row">
      <button
        class="btn btn-primary"
        on:click={() => dispatch('save')}
        disabled={saving}
      >
        {saving ? 'Guardando…' : 'Guardar'}
      </button>
    </div>
  </div>
</div>

<style>
.config-section {
  margin-top: 32px;
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  background: var(--surface);
  padding: 20px 24px;
  box-shadow: var(--shadow-sm);
}

.config-header {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 20px;
}

.config-icon { font-size: 1.5rem; }

.config-title {
  font-size: 1rem;
  font-weight: 700;
  color: var(--text);
  margin: 0;
}

.config-sub {
  font-size: 0.78rem;
  color: var(--text-muted);
  margin: 2px 0 0;
}

.config-body { display: flex; flex-direction: column; gap: 16px; }

.config-input-row {
  display: flex;
  gap: 10px;
  align-items: center;
  max-width: 480px;
}
</style>
