<script>
  export let calledTicket = null;
  export let elapsedText = '';
  export let isLlamado = false;
  export let isEnAtencion = false;
</script>

<div class="ticket-panel">
  <div class="tp-header">Turno Actual</div>

  {#if calledTicket}
    <div class="tp-code">{calledTicket.code}</div>

    <div class="tp-status" class:tp-llamado={isLlamado} class:tp-atencion={isEnAtencion}>
      {isLlamado ? '🔔 LLAMADO' : '🩺 EN ATENCIÓN'}
    </div>

    {#if elapsedText}
      <div class="tp-elapsed">
        <span class="tp-elapsed-icon">⏱️</span>
        <span class="tp-elapsed-time">{elapsedText}</span>
      </div>
    {/if}

  {:else}
    <div class="tp-empty">
      <span class="tp-empty-dash">—</span>
      <p>Sin turno activo</p>
      <p class="tp-empty-hint">Presione "Llamar Siguiente" para atender</p>
    </div>
  {/if}
</div>

<style>
.ticket-panel {
  background: white;
  border: 1px solid var(--border);
  border-radius: var(--radius-xl);
  padding: 32px;
  display: flex;
  flex-direction: column;
  align-items: center;
  min-height: 320px;
  justify-content: center;
  box-shadow: var(--shadow-sm);
}
.tp-header {
  font-size: .7rem;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: .15em;
  color: var(--text-muted);
  margin-bottom: 16px;
}
.tp-code {
  font-size: clamp(4rem, 10vw, 7rem);
  font-weight: 900;
  color: var(--primary-dark);
  line-height: 1;
  letter-spacing: -3px;
  text-align: center;
}
.tp-status {
  margin-top: 12px;
  font-size: .85rem;
  font-weight: 700;
  padding: 5px 20px;
  border-radius: 99px;
}
.tp-llamado {
  background: #fef3c7;
  color: #92400e;
}
.tp-atencion {
  background: #dcfce7;
  color: #166534;
}
.tp-elapsed {
  margin-top: 16px;
  display: flex;
  align-items: center;
  gap: 6px;
  color: var(--text-muted);
}
.tp-elapsed-time {
  font-size: 1.75rem;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  color: var(--text);
}
.tp-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  color: var(--text-muted);
  text-align: center;
}
.tp-empty-dash {
  font-size: 4rem;
  color: var(--border);
  line-height: 1;
}
.tp-empty p { margin: 0; font-size: .95rem; }
.tp-empty-hint { font-size: .8rem !important; color: var(--text-xs); margin-top: 8px !important; }
</style>
