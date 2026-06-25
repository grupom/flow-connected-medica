<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { systemSettings } from '$lib/stores.js';
  import { locale } from '$lib/i18n';
  import { toasts } from '$lib/stores.js';

  let loading = true;
  let saving  = false;
  let multiLanguage = false;

  onMount(async () => {
    try {
      const res = await api.get('/api/admin/settings');
      systemSettings.set(res.data);
      multiLanguage = res.data.multi_language ?? false;
    } catch {
      toasts.error('Error al cargar la configuración.');
    } finally {
      loading = false;
    }
  });

  async function save() {
    saving = true;
    try {
      const res = await api.patch('/api/admin/settings', { multi_language: multiLanguage });
      systemSettings.set(res.data);
      if (!multiLanguage) locale.set('es');
      toasts.success('Configuración guardada.');
    } catch {
      toasts.error('Error al guardar la configuración.');
    } finally {
      saving = false;
    }
  }
</script>

<svelte:head>
  <title>Idiomas — Settings</title>
</svelte:head>

<a href="/admin/settings" class="back-link">← Settings</a>

<div class="page-header">
  <div class="header-icon">🌐</div>
  <div>
    <h2 class="page-title">Idiomas</h2>
    <p class="page-desc">Configura el soporte de idiomas de la aplicación.</p>
  </div>
</div>

{#if loading}
  <div class="loading">Cargando…</div>
{:else}
  <div class="card">
    <div class="section-title">Soporte multi-idioma</div>

    <div class="lang-option" class:lang-option--active={!multiLanguage} on:click={() => multiLanguage = false} role="button" tabindex="0" on:keydown={e => e.key === 'Enter' && (multiLanguage = false)}>
      <div class="lang-flag">🇪🇸</div>
      <div class="lang-info">
        <span class="lang-name">Solo Español</span>
        <span class="lang-hint">El selector de idioma queda oculto en toda la aplicación.</span>
      </div>
      <div class="radio" class:radio--on={!multiLanguage}></div>
    </div>

    <div class="lang-option" class:lang-option--active={multiLanguage} on:click={() => multiLanguage = true} role="button" tabindex="0" on:keydown={e => e.key === 'Enter' && (multiLanguage = true)}>
      <div class="lang-flag">🌐</div>
      <div class="lang-info">
        <span class="lang-name">Multi-idioma — Español + Kreyòl Ayisyen</span>
        <span class="lang-hint">Activa el selector de idioma en la pantalla de login, kiosco y pantallas de turno.</span>
      </div>
      <div class="radio" class:radio--on={multiLanguage}></div>
    </div>

    <div class="actions">
      <a href="/admin/settings" class="btn-ghost">Cancelar</a>
      <button class="btn-primary" on:click={save} disabled={saving}>
        {saving ? 'Guardando…' : 'Guardar cambios'}
      </button>
    </div>
  </div>
{/if}

<style>
/* Back link */
.back-link { display: inline-flex; align-items: center; gap: 4px; font-size: .8125rem; font-weight: 600; color: var(--text-muted); text-decoration: none; margin-bottom: 14px; transition: color .15s; }
.back-link:hover { color: var(--primary); }

/* Header */
.page-header {
  display: flex;
  align-items: center;
  gap: 16px;
  margin-bottom: 28px;
}
.header-icon {
  font-size: 2rem;
  width: 52px;
  height: 52px;
  background: var(--primary-light);
  border-radius: var(--radius);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.page-title {
  font-size: 1.375rem;
  font-weight: 700;
  color: var(--text);
  margin: 0 0 4px;
}
.page-desc {
  font-size: 0.875rem;
  color: var(--text-muted);
  margin: 0;
}

.loading {
  color: var(--text-muted);
  font-size: 0.875rem;
}

/* Card */
.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: 24px;
  display: flex;
  flex-direction: column;
  gap: 16px;
  max-width: 600px;
}

.section-title {
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--text-muted);
  margin-bottom: 4px;
}

/* Language option rows */
.lang-option {
  display: flex;
  align-items: center;
  gap: 14px;
  border: 1.5px solid var(--border);
  border-radius: var(--radius);
  padding: 14px 16px;
  cursor: pointer;
  transition: border-color 0.15s, background 0.15s;
  user-select: none;
}
.lang-option:hover {
  border-color: var(--primary);
  background: var(--primary-light);
}
.lang-option--active {
  border-color: var(--primary);
  background: var(--primary-light);
}

.lang-flag {
  font-size: 1.75rem;
  flex-shrink: 0;
}
.lang-info {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 3px;
}
.lang-name {
  font-size: 0.9375rem;
  font-weight: 600;
  color: var(--text);
}
.lang-hint {
  font-size: 0.8125rem;
  color: var(--text-muted);
  line-height: 1.4;
}

/* Radio indicator */
.radio {
  flex-shrink: 0;
  width: 20px;
  height: 20px;
  border-radius: 50%;
  border: 2px solid var(--border);
  background: white;
  transition: border-color 0.15s, background 0.15s;
  position: relative;
}
.radio--on {
  border-color: var(--primary);
  background: var(--primary);
}
.radio--on::after {
  content: '';
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: white;
}

/* Actions */
.actions {
  display: flex;
  justify-content: flex-end;
  align-items: center;
  gap: 8px;
  padding-top: 8px;
  border-top: 1px solid var(--border);
  margin-top: 4px;
}

.btn-primary {
  padding: 8px 20px;
  background: var(--primary);
  color: #fff;
  border: none;
  border-radius: var(--radius-sm);
  font-size: 0.875rem;
  font-weight: 600;
  cursor: pointer;
  transition: opacity 0.15s;
}
.btn-primary:disabled { opacity: 0.6; cursor: not-allowed; }
.btn-primary:hover:not(:disabled) { opacity: 0.88; }

.btn-ghost {
  padding: 8px 16px;
  background: transparent;
  color: var(--text-muted);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  font-size: 0.875rem;
  font-weight: 500;
  cursor: pointer;
  text-decoration: none;
  display: inline-flex;
  align-items: center;
  transition: background 0.15s, color 0.15s;
}
.btn-ghost:hover { background: var(--border); color: var(--text); }
</style>
