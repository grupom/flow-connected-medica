<script>
  import { createEventDispatcher } from 'svelte';

  export let actionLoading = false;
  export let hasTicket = false;
  export let isLlamado = false;
  export let isEnAtencion = false;

  const dispatch = createEventDispatcher();
</script>

<div class="controls-panel">
  <div class="cp-section">
    <div class="cp-title">Controles de Cola</div>
    <div class="cp-buttons">
      <button
        class="ctrl-btn ctrl-call"
        on:click={() => dispatch('call-next')}
        disabled={actionLoading || hasTicket}
        title={hasTicket ? 'Finalice el turno actual primero' : 'Llamar siguiente turno'}
      >
        <span class="ctrl-icon">📢</span>
        <span>Llamar Siguiente</span>
      </button>

      <button
        class="ctrl-btn ctrl-recall"
        on:click={() => dispatch('recall')}
        disabled={actionLoading || !isLlamado}
        title="Re-anunciar turno actual"
      >
        <span class="ctrl-icon">🔔</span>
        <span>Re-llamar</span>
      </button>
    </div>
  </div>

  <div class="cp-divider"></div>

  <div class="cp-section">
    <div class="cp-title">Atención</div>
    <div class="cp-buttons">
      <button
        class="ctrl-btn ctrl-start"
        on:click={() => dispatch('start')}
        disabled={actionLoading || !isLlamado}
        title="Iniciar atención del paciente"
      >
        <span class="ctrl-icon">▶️</span>
        <span>Iniciar Atención</span>
      </button>

      <button
        class="ctrl-btn ctrl-finish"
        on:click={() => dispatch('finish')}
        disabled={actionLoading || !isEnAtencion}
        title="Finalizar atención"
      >
        <span class="ctrl-icon">✅</span>
        <span>Finalizar Atención</span>
      </button>
    </div>
  </div>

  <div class="cp-divider"></div>

  <div class="cp-section">
    <div class="cp-title">Acciones Adicionales</div>
    <div class="cp-buttons cp-buttons-sm">
      <button
        class="ctrl-btn ctrl-noshow"
        on:click={() => dispatch('no-show')}
        disabled={actionLoading || !isLlamado}
        title="Paciente no se presentó"
      >
        <span class="ctrl-icon">🚫</span>
        <span>No-Show</span>
      </button>

      <button
        class="ctrl-btn ctrl-cancel"
        on:click={() => dispatch('cancel')}
        disabled={actionLoading || !hasTicket}
        title="Cancelar turno"
      >
        <span class="ctrl-icon">✕</span>
        <span>Cancelar</span>
      </button>

      <button
        class="ctrl-btn ctrl-transfer"
        on:click={() => dispatch('transfer')}
        disabled={actionLoading || !hasTicket}
        title="Transferir a otro servicio"
      >
        <span class="ctrl-icon">🔄</span>
        <span>Transferir</span>
      </button>

      <button
        class="ctrl-btn ctrl-requeue"
        on:click={() => dispatch('open-requeue')}
        disabled={actionLoading}
        title="Ver y reinsertar turnos marcados como No-Show"
      >
        <span class="ctrl-icon">↩️</span>
        <span>Reinsertar No-Show</span>
      </button>
    </div>
  </div>
</div>

<style>
.controls-panel {
  background: white;
  border: 1px solid var(--border);
  border-radius: var(--radius-xl);
  padding: 24px;
  box-shadow: var(--shadow-sm);
}
.cp-section { margin-bottom: 4px; }
.cp-title {
  font-size: .7rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .08em;
  color: var(--text-muted);
  margin-bottom: 10px;
}
.cp-buttons {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.cp-buttons-sm {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}
.cp-buttons-sm .ctrl-btn {
  min-width: 0;
}
.cp-divider {
  height: 1px;
  background: var(--border);
  margin: 14px 0;
}

.ctrl-btn {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 16px;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  background: white;
  font-size: .875rem;
  font-weight: 600;
  cursor: pointer;
  transition: all .15s;
  color: var(--text);
  width: 100%;
  justify-content: center;
}
.ctrl-btn:hover:not(:disabled) {
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(0,0,0,.08);
}
.ctrl-btn:disabled {
  opacity: 0.35;
  cursor: not-allowed;
  transform: none;
}
.ctrl-icon { font-size: 1rem; }

/* Button variants */
.ctrl-call { background: var(--primary); color: white; border-color: var(--primary); }
.ctrl-call:hover:not(:disabled) { background: var(--primary-dark); }
.ctrl-recall { background: #f8fafc; border-color: #e2e8f0; }
.ctrl-recall:hover:not(:disabled) { background: #eef2ff; border-color: var(--primary); color: var(--primary); }
.ctrl-start { background: #f0fdf4; border-color: #86efac; color: #166534; }
.ctrl-start:hover:not(:disabled) { background: #dcfce7; }
.ctrl-finish { background: #166534; color: white; border-color: #166534; }
.ctrl-finish:hover:not(:disabled) { background: #15803d; }
.ctrl-noshow { background: #fffbeb; border-color: #fcd34d; color: #92400e; }
.ctrl-noshow:hover:not(:disabled) { background: #fef3c7; }
.ctrl-cancel { background: #fef2f2; border-color: #fca5a5; color: #991b1b; }
.ctrl-cancel:hover:not(:disabled) { background: #fee2e2; }
.ctrl-transfer { background: #f0f9ff; border-color: #93c5fd; color: #1d4ed8; }
.ctrl-transfer:hover:not(:disabled) { background: #dbeafe; }
.ctrl-requeue { background: #faf5ff; border-color: #d8b4fe; color: #6b21a8; }
.ctrl-requeue:hover:not(:disabled) { background: #f3e8ff; }

@media (max-width: 900px) {
  .cp-buttons-sm {
    grid-template-columns: 1fr;
  }
}
</style>
