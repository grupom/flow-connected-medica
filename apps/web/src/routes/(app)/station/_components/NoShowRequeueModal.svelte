<script>
  import { createEventDispatcher } from 'svelte';
  import Modal from '$lib/components/Modal.svelte';

  export let open = false;
  export let noShowList = [];
  export let loading = false;
  export let requeuingTicketId = null;

  const dispatch = createEventDispatcher();

  function close() {
    dispatch('close');
  }

  function timeAgo(iso) {
    if (!iso) return '—';
    const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
    if (mins < 1) return 'hace un momento';
    if (mins < 60) return `hace ${mins} min`;
    return `hace ${Math.floor(mins / 60)}h ${mins % 60}min`;
  }
</script>

<Modal bind:open title="Turnos No-Show — Reinsertar" size="lg" on:close={close}>
  {#if loading}
    <p class="text-sm muted">Cargando…</p>
  {:else if noShowList.length === 0}
    <p class="text-sm muted">No hay turnos marcados como No-Show hoy para esta cola.</p>
  {:else}
    <div class="noshow-list">
      {#each noShowList as t (t.ticket_id)}
        <div class="noshow-row">
          <div class="noshow-info">
            <strong class="noshow-code">{t.code}</strong>
            <span class="noshow-meta">
              No-Show {timeAgo(t.called_at)} · brecha: {t.gap} turno(s)
              {#if t.visit_plan_id}
                <span class="noshow-badge">· visita multi-área</span>
              {/if}
            </span>
          </div>
          <button
            class="btn btn-primary btn-sm"
            disabled={!t.eligible || requeuingTicketId === t.ticket_id}
            title={t.eligible
              ? (t.visit_plan_id ? 'Reinsertar en la cola (sin límite: es parte de una visita multi-área)' : 'Reinsertar en la cola')
              : `Bloqueado: ya se llamaron ${t.gap} turnos después (límite excedido)`}
            on:click={() => dispatch('requeue', t.ticket_id)}
          >
            {requeuingTicketId === t.ticket_id ? 'Reinsertando…' : 'Reinsertar'}
          </button>
        </div>
      {/each}
    </div>
  {/if}
</Modal>

<style>
.noshow-list { display: flex; flex-direction: column; gap: 8px; max-height: 400px; overflow-y: auto; }
.noshow-row {
  display: flex; align-items: center; justify-content: space-between; gap: 12px;
  padding: 10px 14px; border: 1px solid var(--border); border-radius: var(--radius-sm);
}
.noshow-info { display: flex; flex-direction: column; gap: 2px; }
.noshow-code { font-size: 1rem; color: var(--text); }
.noshow-meta { font-size: .75rem; color: var(--text-muted); }
.noshow-badge { color: var(--primary); font-weight: 600; }
</style>
