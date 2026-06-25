<script>
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';

  // ── Ticket settings ────────────────────────────────────────
  let ticketCompanyName = '';
  let savingTicket = false;

  onMount(async () => {
    try {
      const res = await api.get('/api/admin/settings');
      ticketCompanyName = res.data?.ticket_company_name ?? '';
    } catch {
      // non-critical
    }
  });

  async function saveTicketSettings() {
    savingTicket = true;
    try {
      await api.patch('/api/admin/settings', {
        ticket_company_name: ticketCompanyName.trim()
      });
      toasts.success('Configuración del ticket guardada');
    } catch (e) {
      toasts.error(e.message || 'Error al guardar');
    } finally {
      savingTicket = false;
    }
  }

  const sections = [
    {
      href:    '/admin/stations',
      icon:    '🖥️',
      title:   'Stations',
      desc:    'Configura las estaciones de atención y operadores.',
    },
    {
      href:    '/admin/kiosks',
      icon:    '🎟️',
      title:   'Kiosks',
      desc:    'Gestiona los quioscos de autoservicio y sus colas habilitadas.',
    },
    {
      href:    '/admin/roles',
      icon:    '🔑',
      title:   'Roles',
      desc:    'Define los roles del sistema y sus permisos de acceso.',
    },
    {
      href:    '/admin/users',
      icon:    '👥',
      title:   'Users',
      desc:    'Administra los usuarios, credenciales y roles asignados.',
    },
    {
      href:    '/admin/queue-settings',
      icon:    '⚙️',
      title:   'Module Prefixes',
      desc:    'Configura los prefijos de cola, reglas de generación de turnos y prioridades.',
    },
    {
      href:    '/admin/settings/language',
      icon:    '🌐',
      title:   'Idiomas',
      desc:    'Activa o desactiva el soporte multi-idioma (Español / Kreyòl Ayisyen).',
    },
  ];

  // ── Factory Reset ──────────────────────────────────────────
  let showResetModal = false;
  let confirmText    = '';
  let resetting      = false;

  const CONFIRM_WORD = 'RESET';

  function openReset()  { showResetModal = true; confirmText = ''; }
  function closeReset() { showResetModal = false; confirmText = ''; }

  async function doFactoryReset() {
    if (confirmText.trim().toUpperCase() !== CONFIRM_WORD) return;
    resetting = true;
    try {
      await api.post('/api/admin/settings/factory-reset', {});
      toasts.success('Sistema reiniciado correctamente. Todos los datos operativos fueron eliminados.');
      closeReset();
    } catch (e) {
      toasts.error(e.message || 'Error al reiniciar el sistema.');
    } finally {
      resetting = false;
    }
  }
</script>

<svelte:head>
  <title>Settings — Flow Connected</title>
</svelte:head>

<div class="page-header">
  <h2 class="page-title">Settings</h2>
  <p class="page-subtitle">Configuración y administración del sistema</p>
</div>

<div class="settings-grid">
  {#each sections as s}
    <a href={s.href} class="setting-card">
      <div class="card-icon">{s.icon}</div>
      <div class="card-body">
        <span class="card-title">{s.title}</span>
        <span class="card-desc">{s.desc}</span>
      </div>
      <span class="card-arrow">→</span>
    </a>
  {/each}
</div>

<!-- ── Ticket config ────────────────────────────────────────── -->
<div class="config-section">
  <div class="config-header">
    <span class="config-icon">🖨️</span>
    <div>
      <h3 class="config-title">Configuración del Ticket</h3>
      <p class="config-sub">Personaliza el encabezado que aparece en el ticket impreso</p>
    </div>
  </div>

  <div class="config-body">
    <div class="config-field">
      <label class="config-label" for="company-name">
        Nombre de la empresa
        <span class="config-hint">Aparece encima de "FLOW CONNECTED" en el ticket</span>
      </label>
      <div class="config-input-row">
        <input
          id="company-name"
          class="input"
          type="text"
          bind:value={ticketCompanyName}
          placeholder="Ej. MEDICA"
          maxlength="40"
          on:keydown={e => e.key === 'Enter' && saveTicketSettings()}
        />
        <button
          class="btn btn-primary"
          on:click={saveTicketSettings}
          disabled={savingTicket}
        >
          {savingTicket ? 'Guardando…' : 'Guardar'}
        </button>
      </div>
      {#if ticketCompanyName.trim()}
        <div class="ticket-preview">
          <span class="tp-company">{ticketCompanyName.trim().toUpperCase()}</span>
          <span class="tp-brand">FLOW CONNECTED</span>
        </div>
      {/if}
    </div>
  </div>
</div>

<!-- ── Danger Zone ──────────────────────────────────────────── -->
<div class="danger-zone">
  <div class="dz-header">
    <span class="dz-icon">⚠️</span>
    <div>
      <h3 class="dz-title">Zona de Peligro</h3>
      <p class="dz-sub">Acciones irreversibles — úselas con precaución</p>
    </div>
  </div>

  <div class="dz-action">
    <div class="dz-action-info">
      <span class="dz-action-title">Reinicio de Fábrica</span>
      <span class="dz-action-desc">
        Elimina todos los turnos, estaciones, módulos, kioscos, boards, prefijos de cola y
        cierres diarios. Reinicia los contadores a 1. Los usuarios y roles se conservan.
      </span>
    </div>
    <button class="btn-danger" on:click={openReset}>
      🗑️ Reiniciar Sistema
    </button>
  </div>
</div>

<!-- ── Confirmation Modal ───────────────────────────────────── -->
{#if showResetModal}
  <div class="modal-backdrop" on:click|self={closeReset}>
    <div class="modal-box" role="dialog" aria-modal="true">
      <div class="modal-icon">⚠️</div>
      <h3 class="modal-title">¿Estás seguro?</h3>
      <p class="modal-body">
        Esta acción <strong>no se puede deshacer</strong>. Se eliminarán permanentemente:
      </p>
      <ul class="modal-list">
        <li>Todos los turnos y eventos</li>
        <li>Estaciones y módulos</li>
        <li>Kioscos y boards</li>
        <li>Prefijos de cola (queue settings)</li>
        <li>Registros de cierre diario</li>
      </ul>
      <p class="modal-confirm-label">
        Escribe <strong>{CONFIRM_WORD}</strong> para confirmar:
      </p>
      <input
        class="modal-input"
        type="text"
        placeholder={CONFIRM_WORD}
        bind:value={confirmText}
        on:keydown={e => e.key === 'Enter' && doFactoryReset()}
        autocomplete="off"
        spellcheck="false"
      />
      <div class="modal-actions">
        <button class="btn-secondary" on:click={closeReset} disabled={resetting}>
          Cancelar
        </button>
        <button
          class="btn-danger"
          on:click={doFactoryReset}
          disabled={confirmText.trim().toUpperCase() !== CONFIRM_WORD || resetting}
        >
          {#if resetting}
            <span class="spinner"></span> Reiniciando…
          {:else}
            🗑️ Confirmar Reinicio
          {/if}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
/* ── Settings grid ───────────────────────────────────────── */
.settings-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 16px;
  margin-top: 8px;
}

.setting-card {
  display: flex;
  align-items: center;
  gap: 16px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: 20px;
  text-decoration: none;
  color: inherit;
  transition: border-color 0.15s, box-shadow 0.15s, transform 0.15s;
  box-shadow: var(--shadow-sm);
  cursor: pointer;
}

.setting-card:hover {
  border-color: var(--primary);
  box-shadow: 0 4px 16px rgba(59, 130, 246, 0.12);
  transform: translateY(-2px);
}

.card-icon {
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

.card-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.card-title {
  font-size: 0.9375rem;
  font-weight: 700;
  color: var(--text);
}

.card-desc {
  font-size: 0.8rem;
  color: var(--text-muted);
  line-height: 1.45;
}

.card-arrow {
  font-size: 1.1rem;
  color: var(--text-muted);
  transition: color 0.15s, transform 0.15s;
  flex-shrink: 0;
}

.setting-card:hover .card-arrow {
  color: var(--primary);
  transform: translateX(3px);
}

/* ── Ticket config section ───────────────────────────────── */
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

.config-field { display: flex; flex-direction: column; gap: 8px; }

.config-label {
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--text);
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.config-hint {
  font-size: 0.75rem;
  font-weight: 400;
  color: var(--text-muted);
}

.config-input-row {
  display: flex;
  gap: 10px;
  align-items: center;
  max-width: 480px;
}

.config-input-row .input { flex: 1; }

/* Mini ticket preview */
.ticket-preview {
  display: inline-flex;
  flex-direction: column;
  align-items: center;
  gap: 1px;
  background: #f8fafc;
  border: 1px dashed var(--border);
  border-radius: var(--radius);
  padding: 8px 20px;
  margin-top: 4px;
  width: fit-content;
}

.tp-company {
  font-size: 0.7rem;
  font-weight: 800;
  letter-spacing: 0.12em;
  color: var(--text);
}

.tp-brand {
  font-size: 0.6rem;
  font-weight: 600;
  letter-spacing: 0.1em;
  color: var(--text-muted);
}

/* ── Danger zone ─────────────────────────────────────────── */
.danger-zone {
  margin-top: 40px;
  border: 1.5px solid #fca5a5;
  border-radius: var(--radius-lg);
  background: #fff5f5;
  padding: 20px 24px;
}

.dz-header {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 20px;
}

.dz-icon { font-size: 1.5rem; }

.dz-title {
  font-size: 1rem;
  font-weight: 700;
  color: #b91c1c;
  margin: 0;
}

.dz-sub {
  font-size: 0.78rem;
  color: #ef4444;
  margin: 2px 0 0;
}

.dz-action {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 24px;
  background: white;
  border: 1px solid #fca5a5;
  border-radius: var(--radius);
  padding: 16px 20px;
  flex-wrap: wrap;
}

.dz-action-info {
  display: flex;
  flex-direction: column;
  gap: 4px;
  flex: 1;
  min-width: 200px;
}

.dz-action-title {
  font-size: 0.9rem;
  font-weight: 700;
  color: var(--text);
}

.dz-action-desc {
  font-size: 0.8rem;
  color: var(--text-muted);
  line-height: 1.5;
}

.btn-danger {
  background: #ef4444;
  color: white;
  border: none;
  border-radius: var(--radius);
  padding: 10px 18px;
  font-size: 0.875rem;
  font-weight: 600;
  cursor: pointer;
  white-space: nowrap;
  display: flex;
  align-items: center;
  gap: 6px;
  transition: background 0.15s;
  flex-shrink: 0;
}

.btn-danger:hover:not(:disabled) { background: #dc2626; }
.btn-danger:disabled { opacity: 0.5; cursor: not-allowed; }

/* ── Modal ───────────────────────────────────────────────── */
.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999;
  padding: 16px;
}

.modal-box {
  background: white;
  border-radius: var(--radius-lg);
  padding: 32px 28px;
  max-width: 460px;
  width: 100%;
  box-shadow: 0 25px 50px rgba(0,0,0,0.25);
  text-align: center;
}

.modal-icon { font-size: 3rem; margin-bottom: 12px; }

.modal-title {
  font-size: 1.25rem;
  font-weight: 800;
  color: #b91c1c;
  margin: 0 0 12px;
}

.modal-body {
  font-size: 0.875rem;
  color: var(--text-muted);
  margin: 0 0 12px;
  line-height: 1.5;
}

.modal-list {
  text-align: left;
  font-size: 0.8rem;
  color: var(--text-muted);
  margin: 0 0 20px;
  padding-left: 20px;
  line-height: 1.8;
}

.modal-confirm-label {
  font-size: 0.85rem;
  color: var(--text);
  margin-bottom: 8px;
}

.modal-input {
  width: 100%;
  box-sizing: border-box;
  padding: 10px 14px;
  border: 2px solid #fca5a5;
  border-radius: var(--radius);
  font-size: 1rem;
  font-weight: 700;
  text-align: center;
  letter-spacing: 0.1em;
  outline: none;
  margin-bottom: 20px;
  transition: border-color 0.15s;
}

.modal-input:focus { border-color: #ef4444; }

.modal-actions {
  display: flex;
  gap: 12px;
  justify-content: center;
}

.btn-secondary {
  background: var(--surface);
  color: var(--text);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 10px 20px;
  font-size: 0.875rem;
  font-weight: 600;
  cursor: pointer;
  transition: background 0.15s;
}

.btn-secondary:hover:not(:disabled) { background: var(--border); }
.btn-secondary:disabled { opacity: 0.5; cursor: not-allowed; }

.spinner {
  display: inline-block;
  width: 14px;
  height: 14px;
  border: 2px solid rgba(255,255,255,0.4);
  border-top-color: white;
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
}

@keyframes spin { to { transform: rotate(360deg); } }

@media (max-width: 600px) {
  .settings-grid { grid-template-columns: 1fr; }
  .dz-action { flex-direction: column; align-items: flex-start; }
}
</style>
