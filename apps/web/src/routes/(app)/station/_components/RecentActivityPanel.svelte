<script>
  export let recentTickets = [];

  function statusLabel(s) {
    const map = { 'waiting':'En Espera', 'serving':'Atendiendo', 'done':'Finalizado', 'no_show':'No-Show', 'cancelled':'Cancelado' };
    return map[s] || s;
  }
  function statusClass(s) {
    const map = { 'waiting':'badge-warning', 'serving':'badge-success', 'done':'badge-primary', 'no_show':'badge-danger', 'cancelled':'badge-gray' };
    return map[s] || 'badge-gray';
  }
</script>

<div class="activity-panel">
  <div class="ap-title">Actividad Reciente</div>
  {#if recentTickets.length === 0}
    <p class="ap-empty">Sin actividad reciente</p>
  {:else}
    <div class="ap-list">
      {#each recentTickets as t}
        <div class="ap-row">
          <strong class="ap-code">{t.ticket_number}</strong>
          <span class="ap-module">{t.module_name || t.station_name || '—'}</span>
          <span class="badge {statusClass(t.status)}">{statusLabel(t.status)}</span>
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
.activity-panel {
  background: white;
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: 16px 20px;
  box-shadow: var(--shadow-sm);
}
.ap-title {
  font-size: .7rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .08em;
  color: var(--text-muted);
  margin-bottom: 10px;
}
.ap-empty {
  color: var(--text-muted);
  font-size: .85rem;
}
.ap-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
  max-height: 200px;
  overflow-y: auto;
}
.ap-row {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: .85rem;
  padding: 4px 0;
  border-bottom: 1px solid var(--border);
}
.ap-row:last-child { border-bottom: none; }
.ap-code { min-width: 50px; color: var(--text); }
.ap-module { flex: 1; color: var(--text-muted); font-size: .8rem; }
</style>
