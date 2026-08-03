<script>
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';

  let showResetModal = false;
  let confirmText    = '';
  let resetPassword   = '';
  let resetting      = false;

  const CONFIRM_WORD = 'RESET';

  function openReset()  { showResetModal = true; confirmText = ''; resetPassword = ''; }
  function closeReset() { showResetModal = false; confirmText = ''; resetPassword = ''; }

  async function doFactoryReset() {
    if (confirmText.trim().toUpperCase() !== CONFIRM_WORD || !resetPassword) return;
    resetting = true;
    try {
      await api.post('/api/admin/settings/factory-reset', { password: resetPassword });
      toasts.success('Sistema reiniciado correctamente. Todos los datos operativos fueron eliminados.');
      closeReset();
    } catch (e) {
      toasts.error(e.message || 'Error al reiniciar el sistema.');
    } finally {
      resetting = false;
    }
  }
</script>

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
      <p class="modal-confirm-label">
        Ingresa tu contraseña para confirmar tu identidad:
      </p>
      <input
        class="modal-input modal-input-password"
        type="password"
        placeholder="Contraseña"
        bind:value={resetPassword}
        on:keydown={e => e.key === 'Enter' && doFactoryReset()}
        autocomplete="current-password"
      />
      <div class="modal-actions">
        <button class="btn-secondary" on:click={closeReset} disabled={resetting}>
          Cancelar
        </button>
        <button
          class="btn-danger"
          on:click={doFactoryReset}
          disabled={confirmText.trim().toUpperCase() !== CONFIRM_WORD || !resetPassword || resetting}
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
  .dz-action { flex-direction: column; align-items: flex-start; }
}
</style>
