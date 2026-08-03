<script>
  import { onMount, onDestroy } from 'svelte';
  import { api } from '$lib/api.js';
  import { auth } from '$lib/auth.js';
  import { toasts } from '$lib/stores.js';
  import TicketPanel from './_components/TicketPanel.svelte';
  import ControlsPanel from './_components/ControlsPanel.svelte';
  import QueueStatsPanel from './_components/QueueStatsPanel.svelte';
  import RecentActivityPanel from './_components/RecentActivityPanel.svelte';
  import TransferModal from './_components/TransferModal.svelte';
  import NoShowRequeueModal from './_components/NoShowRequeueModal.svelte';

  // ── State ──────────────────────────────────────────────
  let stations = [];
  let selectedStationId = '';
  let selectedStation = null;
  let queueSettings = [];
  let calledTicket = null;
  let loading = true;
  let actionLoading = false;
  let pollInterval;
  let elapsedInterval;

  // Queue stats
  let stats = { waiting: 0, serving: 0, done: 0, noShow: 0 };
  let recentTickets = [];

  // Elapsed time
  let elapsedText = '';

  // Transfer State
  let showTransferModal = false;
  let transferModalRef;

  // No-Show Requeue State
  let showNoShowModal = false;
  let noShowList = [];
  let loadingNoShowList = false;
  let requeuingTicketId = null;

  // ── Derived ────────────────────────────────────────────
  $: selectedStation = stations.find(s => s.station_id == selectedStationId) || null;
  $: stationPrefix = selectedStation?.prefix ?? '';
  $: hasTicket = !!calledTicket;
  $: isLlamado = calledTicket?.status === 'LLAMADO';
  $: isEnAtencion = calledTicket?.status === 'EN_ATENCION';

  // ── Load ───────────────────────────────────────────────
  async function load() {
    loading = true;
    try {
      const [s, q] = await Promise.all([
        api.get('/api/my-stations'),
        api.get('/api/admin/queue-settings').catch(() => null),
      ]);
      stations = s?.data ?? s ?? [];
      queueSettings = q?.data ?? q ?? [];
      if (!selectedStationId && stations.length > 0) {
        selectedStationId = stations[0].station_id;
      }
    } catch (e) {
      toasts.error(e.message);
    } finally {
      loading = false;
    }
  }

  // ── Refresh queue data ─────────────────────────────────
  async function refreshQueue() {
    if (!stationPrefix || !selectedStationId) return;
    try {
      // Pass ?prefix= so the API filters stats & activity to this station's queue
      // (includes priority-child prefixes automatically on the server side)
      const res = await api.get(`/api/admin/metrics?prefix=${encodeURIComponent(stationPrefix)}`);
      const data = res?.data ?? res;
      const s = data?.stats ?? {};
      stats = {
        waiting: s.waiting  || 0,   // already filtered by prefix on server
        serving: s.serving  || 0,
        done:    s.done     || 0,
        noShow:  s.noShow   || 0,
      };
      recentTickets = (data?.tickets ?? []).slice(0, 15);
    } catch { /* silent */ }

    // Find active ticket at this station directly from DB
    try {
      const res = await api.get(`/api/queue/active-ticket/${selectedStationId}`);
      const ticket = res?.data ?? res;
      if (ticket && ticket.ticket_id) {
        calledTicket = {
          ticket_id: ticket.ticket_id,
          code: ticket.code,
          status: ticket.status,
          called_at: ticket.called_at,
          started_at: ticket.started_at,
          module_name: ticket.module_name
        };
      } else {
        calledTicket = null;
      }
    } catch { calledTicket = null; }
  }

  // ── Elapsed time ───────────────────────────────────────
  function updateElapsed() {
    if (!calledTicket) { elapsedText = ''; return; }
    const ref = calledTicket.called_at || calledTicket.started_at;
    if (!ref) { elapsedText = ''; return; }
    const diff = Math.floor((Date.now() - new Date(ref).getTime()) / 1000);
    const m = Math.floor(diff / 60);
    const s = diff % 60;
    elapsedText = `${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
  }

  // ── Queue Actions ──────────────────────────────────────
  async function callNext() {
    if (!selectedStationId) return;
    actionLoading = true;
    try {
      const res = await api.post('/api/queue/call-next', {
        station_id: Number(selectedStationId),
        user_id: $auth.user?.user_id
      });
      const ticket = res?.data ?? res;
      calledTicket = {
        ticket_id: ticket.ticket_id,
        code: ticket.code,
        status: 'LLAMADO',
        called_at: ticket.called_at || new Date().toISOString(),
        module_name: ticket.module_name
      };
      toasts.success(`Llamando: ${ticket.code}`);
      await refreshQueue();
    } catch (e) {
      toasts.error(e.message || 'No hay tickets en espera');
    } finally {
      actionLoading = false;
    }
  }

  async function recallTicket() {
    if (!calledTicket || calledTicket.status !== 'LLAMADO') return;
    actionLoading = true;
    try {
      await api.post('/api/queue/recall', {
        ticket_id: calledTicket.ticket_id,
        station_id: Number(selectedStationId),
        user_id: $auth.user?.user_id
      });
      toasts.success('Turno re-llamado 🔔');
    } catch (e) {
      toasts.error(e.message || 'Error al re-llamar');
    } finally {
      actionLoading = false;
    }
  }

  async function startService() {
    if (!calledTicket || calledTicket.status !== 'LLAMADO') return;
    actionLoading = true;
    try {
      await api.post('/api/queue/start', {
        ticket_id: calledTicket.ticket_id,
        station_id: Number(selectedStationId),
        user_id: $auth.user?.user_id
      });
      calledTicket = { ...calledTicket, status: 'EN_ATENCION', started_at: new Date().toISOString() };
      toasts.success('Atención iniciada');
      await refreshQueue();
    } catch (e) {
      toasts.error(e.message || 'Error al iniciar atención');
    } finally {
      actionLoading = false;
    }
  }

  async function finishService() {
    if (!calledTicket || calledTicket.status !== 'EN_ATENCION') return;
    actionLoading = true;
    try {
      await api.post('/api/queue/finish', {
        ticket_id: calledTicket.ticket_id,
        station_id: Number(selectedStationId),
        user_id: $auth.user?.user_id
      });
      toasts.success('Atención finalizada ✅');
      calledTicket = null;
      await refreshQueue();
    } catch (e) {
      toasts.error(e.message || 'Error al finalizar');
    } finally {
      actionLoading = false;
    }
  }

  async function markNoShow() {
    if (!calledTicket || calledTicket.status !== 'LLAMADO') return;
    actionLoading = true;
    try {
      await api.post('/api/queue/no-show', {
        ticket_id: calledTicket.ticket_id,
        station_id: Number(selectedStationId),
        user_id: $auth.user?.user_id
      });
      toasts.success('Marcado como no-show 🚫');
      calledTicket = null;
      await refreshQueue();
    } catch (e) {
      toasts.error(e.message || 'Error');
    } finally {
      actionLoading = false;
    }
  }

  async function cancelTicket() {
    if (!calledTicket) return;
    actionLoading = true;
    try {
      await api.post('/api/queue/cancel', {
        ticket_id: calledTicket.ticket_id,
        station_id: Number(selectedStationId),
        user_id: $auth.user?.user_id
      });
      toasts.success('Turno cancelado');
      calledTicket = null;
      await refreshQueue();
    } catch (e) {
      toasts.error(e.message || 'Error al cancelar');
    } finally {
      actionLoading = false;
    }
  }

  function openTransfer() {
    if (!calledTicket) return;
    showTransferModal = true;
  }

  async function handleTransfer(e) {
    const { toPrefix, reason } = e.detail;
    if (!calledTicket || !toPrefix) return;
    actionLoading = true;
    try {
      await api.post('/api/queue/transfer', {
        ticket_id: calledTicket.ticket_id,
        station_id: Number(selectedStationId),
        user_id: $auth.user?.user_id,
        to_prefix: toPrefix,
        reason
      });
      toasts.success(`Turno transferido a cola ${toPrefix}`);
      showTransferModal = false;
      calledTicket = null;
      await refreshQueue();
    } catch (e2) {
      toasts.error(e2.message || 'Error en transferencia');
      transferModalRef?.resetSubmitting();
    } finally {
      actionLoading = false;
    }
  }

  async function openNoShowModal() {
    showNoShowModal = true;
    await loadNoShowList();
  }

  async function loadNoShowList() {
    if (!selectedStationId) return;
    loadingNoShowList = true;
    try {
      const res = await api.get(`/api/queue/no-show?station_id=${Number(selectedStationId)}`);
      noShowList = res?.data ?? res ?? [];
    } catch (e) {
      toasts.error(e.message || 'Error al cargar turnos No-Show');
      noShowList = [];
    } finally {
      loadingNoShowList = false;
    }
  }

  async function requeueTicket(e) {
    const ticketId = e.detail;
    requeuingTicketId = ticketId;
    try {
      const res = await api.post('/api/queue/requeue-no-show', {
        ticket_id: ticketId,
        station_id: Number(selectedStationId),
        user_id: $auth.user?.user_id,
      });
      const ticket = res?.data ?? res;
      toasts.success(`Turno ${ticket.code} reinsertado en la cola`);
      await loadNoShowList();
      await refreshQueue();
    } catch (e2) {
      toasts.error(e2.message || 'No se pudo reinsertar el turno');
    } finally {
      requeuingTicketId = null;
    }
  }

  // ── Lifecycle ──────────────────────────────────────────
  onMount(async () => {
    await load();
    await refreshQueue();
    pollInterval = setInterval(refreshQueue, 5000);
    elapsedInterval = setInterval(updateElapsed, 1000);
  });

  onDestroy(() => {
    if (pollInterval) clearInterval(pollInterval);
    if (elapsedInterval) clearInterval(elapsedInterval);
  });

  function onStationChange() {
    calledTicket = null;
    refreshQueue();
  }
</script>

<svelte:head>
  <title>Estación — Flow Connected</title>
</svelte:head>

{#if loading}
  <div class="loading-full">
    <div class="spinner"></div>
    <p>Cargando estación…</p>
  </div>
{:else if stations.length === 0}
  <div class="loading-full">
    <span class="empty-icon">🖥️</span>
    <h3 style="margin:0;color:var(--text)">Sin estaciones asignadas</h3>
    <p style="color:var(--text-muted);text-align:center;max-width:400px">No tiene estaciones asignadas a su cuenta. Contacte al administrador del sistema para que le asigne una estación de trabajo.</p>
  </div>
{:else}

<!-- ═══════ HEADER ═══════ -->
<div class="station-header">
  <div class="sh-left">
    <h1 class="sh-title">Operaciones de Estación</h1>
    <p class="sh-sub">Gestión de atención al paciente</p>
  </div>
  <div class="sh-right">
    <label class="sh-label" for="station-select">Estación</label>
    <select id="station-select" class="sh-select" bind:value={selectedStationId} on:change={onStationChange}>
      {#each stations as s}
        <option value={s.station_id}>
          {s.station_name}
        </option>
      {/each}
    </select>
  </div>
</div>

<!-- ═══════ CONTEXT BANNER ═══════ -->
{#if selectedStation}
  <div class="ctx-banner">
    <div class="ctx-chip">
      <span class="ctx-chip-label">Estación</span>
      <span class="ctx-chip-value">{selectedStation.station_name}</span>
    </div>
    <div class="ctx-sep"></div>
    <div class="ctx-chip">
      <span class="ctx-chip-label">Cola</span>
      <span class="ctx-chip-value ctx-chip-prefix">{stationPrefix}</span>
    </div>
    <div class="ctx-sep"></div>
    <div class="ctx-chip">
      <span class="ctx-chip-label">Operador</span>
      <span class="ctx-chip-value">{$auth.user?.display_name || $auth.user?.username || '—'}</span>
    </div>
  </div>
{/if}

<!-- ═══════ MAIN LAYOUT ═══════ -->
<div class="station-layout">
  <TicketPanel {calledTicket} {elapsedText} {isLlamado} {isEnAtencion} />
  <ControlsPanel
    {actionLoading} {hasTicket} {isLlamado} {isEnAtencion}
    on:call-next={callNext}
    on:recall={recallTicket}
    on:start={startService}
    on:finish={finishService}
    on:no-show={markNoShow}
    on:cancel={cancelTicket}
    on:transfer={openTransfer}
    on:open-requeue={openNoShowModal}
  />
</div>

<!-- ═══════ BOTTOM: Stats + Activity ═══════ -->
<div class="bottom-row">
  <QueueStatsPanel {stats} />
  <RecentActivityPanel {recentTickets} />
</div>

{/if}

<TransferModal
  bind:this={transferModalRef}
  bind:open={showTransferModal}
  ticketCode={calledTicket?.code}
  {queueSettings}
  {stationPrefix}
  on:close={() => showTransferModal = false}
  on:transfer={handleTransfer}
/>

<NoShowRequeueModal
  bind:open={showNoShowModal}
  {noShowList}
  loading={loadingNoShowList}
  {requeuingTicketId}
  on:close={() => showNoShowModal = false}
  on:requeue={requeueTicket}
/>

<style>
/* ═══════ LOADING ═══════ */
.loading-full {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 60vh;
  gap: 16px;
  color: var(--text-muted);
}
.empty-icon { font-size: 3rem; }
.spinner {
  width: 36px; height: 36px;
  border: 3px solid var(--border);
  border-top-color: var(--primary);
  border-radius: 50%;
  animation: spin .7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* ═══════ HEADER ═══════ */
.station-header {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  margin-bottom: 20px;
  flex-wrap: wrap;
  gap: 12px;
}
.sh-title {
  font-size: 1.5rem;
  font-weight: 800;
  color: var(--text);
  margin: 0;
}
.sh-sub {
  font-size: .85rem;
  color: var(--text-muted);
  margin: 2px 0 0;
}
.sh-right {
  display: flex;
  align-items: center;
  gap: 8px;
}
.sh-label {
  font-size: .75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .06em;
  color: var(--text-muted);
  white-space: nowrap;
}
.sh-select {
  padding: 8px 12px;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  background: var(--surface);
  color: var(--text);
  font-size: .875rem;
  font-weight: 500;
  min-width: 240px;
}
.sh-select:focus { border-color: var(--primary); outline: none; }

/* ═══════ CONTEXT BANNER ═══════ */
.ctx-banner {
  display: flex;
  align-items: center;
  gap: 16px;
  background: linear-gradient(135deg, rgba(59,130,246,.08), rgba(59,130,246,.03));
  border: 1px solid rgba(59,130,246,.2);
  border-radius: var(--radius-lg);
  padding: 12px 24px;
  margin-bottom: 20px;
  flex-wrap: wrap;
}
.ctx-chip {
  display: flex;
  flex-direction: column;
  gap: 1px;
}
.ctx-chip-label {
  font-size: .65rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: .1em;
  color: var(--primary);
}
.ctx-chip-value {
  font-size: .95rem;
  font-weight: 600;
  color: var(--text);
}
.ctx-chip-prefix {
  font-size: 1.1rem;
  font-weight: 800;
  color: var(--primary-dark);
}
.ctx-sep {
  width: 1px;
  height: 28px;
  background: var(--primary);
  opacity: 0.15;
}

/* ═══════ MAIN LAYOUT ═══════ */
.station-layout {
  display: grid;
  grid-template-columns: 1.5fr 1fr;
  gap: 20px;
  margin-bottom: 20px;
}

/* ═══════ BOTTOM ROW ═══════ */
.bottom-row {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 20px;
}

/* ═══════ RESPONSIVE ═══════ */
@media (max-width: 900px) {
  .station-layout {
    grid-template-columns: 1fr;
  }
  .bottom-row {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 600px) {
  .ctx-banner {
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
  }
  .ctx-sep { display: none; }
  .station-header { flex-direction: column; align-items: flex-start; }
  .sh-select { min-width: 100%; }
}
</style>
