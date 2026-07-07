<script>
  import { onMount, onDestroy } from 'svelte';
  import { api } from '$lib/api.js';
  import { auth } from '$lib/auth.js';
  import { toasts } from '$lib/stores.js';
  import Modal from '$lib/components/Modal.svelte';
  import { printTicket } from '$lib/printing/printTicket.js';

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
  let transferToPrefix = '';
  let transferReason = '';
  let submittingTransfer = false;

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
      const res = await api.post('/api/queue/finish', {
        ticket_id: calledTicket.ticket_id,
        station_id: Number(selectedStationId),
        user_id: $auth.user?.user_id
      });
      const result = res?.data ?? res;
      toasts.success('Atención finalizada ✅');
      calledTicket = null;

      // If this ticket belongs to a multi-area visit plan, the next step's
      // ticket was just created — print it right here so staff can hand it
      // to the patient immediately.
      if (result?.next_ticket) {
        const nt = result.next_ticket;
        try {
          await printTicket({
            code: nt.code,
            prefix: nt.prefix,
            service_name: nt.service_name,
            tck_number: nt.tck_number,
          });
          toasts.success(`Siguiente turno del plan: ${nt.code} (${nt.service_name}) — impreso`);
        } catch (printErr) {
          toasts.error(`Turno ${nt.code} (${nt.service_name}) creado pero falló al imprimir: ${printErr.message}`);
        }
      }

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
    transferToPrefix = '';
    transferReason = '';
    showTransferModal = true;
  }

  async function handleTransfer() {
    if (!calledTicket || !transferToPrefix) return;
    actionLoading = true;
    submittingTransfer = true;
    try {
      await api.post('/api/queue/transfer', {
        ticket_id: calledTicket.ticket_id,
        station_id: Number(selectedStationId),
        user_id: $auth.user?.user_id,
        to_prefix: transferToPrefix,
        reason: transferReason
      });
      toasts.success(`Turno transferido a cola ${transferToPrefix}`);
      showTransferModal = false;
      calledTicket = null;
      await refreshQueue();
    } catch (e) {
      toasts.error(e.message || 'Error en transferencia');
    } finally {
      actionLoading = false;
      submittingTransfer = false;
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

  async function requeueTicket(ticketId) {
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
    } catch (e) {
      toasts.error(e.message || 'No se pudo reinsertar el turno');
    } finally {
      requeuingTicketId = null;
    }
  }

  function timeAgo(iso) {
    if (!iso) return '—';
    const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
    if (mins < 1) return 'hace un momento';
    if (mins < 60) return `hace ${mins} min`;
    return `hace ${Math.floor(mins / 60)}h ${mins % 60}min`;
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

  // Status badge helpers
  function statusLabel(s) {
    const map = { 'waiting':'En Espera', 'serving':'Atendiendo', 'done':'Finalizado', 'no_show':'No-Show', 'cancelled':'Cancelado' };
    return map[s] || s;
  }
  function statusClass(s) {
    const map = { 'waiting':'badge-warning', 'serving':'badge-success', 'done':'badge-primary', 'no_show':'badge-danger', 'cancelled':'badge-gray' };
    return map[s] || 'badge-gray';
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

  <!-- ── CENTER: Current Ticket ── -->
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

  <!-- ── RIGHT: Controls ── -->
  <div class="controls-panel">
    <div class="cp-section">
      <div class="cp-title">Controles de Cola</div>
      <div class="cp-buttons">
        <button
          class="ctrl-btn ctrl-call"
          on:click={callNext}
          disabled={actionLoading || hasTicket}
          title={hasTicket ? 'Finalice el turno actual primero' : 'Llamar siguiente turno'}
        >
          <span class="ctrl-icon">📢</span>
          <span>Llamar Siguiente</span>
        </button>

        <button
          class="ctrl-btn ctrl-recall"
          on:click={recallTicket}
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
          on:click={startService}
          disabled={actionLoading || !isLlamado}
          title="Iniciar atención del paciente"
        >
          <span class="ctrl-icon">▶️</span>
          <span>Iniciar Atención</span>
        </button>

        <button
          class="ctrl-btn ctrl-finish"
          on:click={finishService}
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
          on:click={markNoShow}
          disabled={actionLoading || !isLlamado}
          title="Paciente no se presentó"
        >
          <span class="ctrl-icon">🚫</span>
          <span>No-Show</span>
        </button>

        <button
          class="ctrl-btn ctrl-cancel"
          on:click={cancelTicket}
          disabled={actionLoading || !hasTicket}
          title="Cancelar turno"
        >
          <span class="ctrl-icon">✕</span>
          <span>Cancelar</span>
        </button>

        <button
          class="ctrl-btn ctrl-transfer"
          on:click={openTransfer}
          disabled={actionLoading || !hasTicket}
          title="Transferir a otro servicio"
        >
          <span class="ctrl-icon">🔄</span>
          <span>Transferir</span>
        </button>

        <button
          class="ctrl-btn ctrl-requeue"
          on:click={openNoShowModal}
          disabled={actionLoading}
          title="Ver y reinsertar turnos marcados como No-Show"
        >
          <span class="ctrl-icon">↩️</span>
          <span>Reinsertar No-Show</span>
        </button>
      </div>
    </div>
  </div>
</div>

<!-- ═══════ BOTTOM: Stats + Activity ═══════ -->
<div class="bottom-row">
  <!-- Queue Stats -->
  <div class="stats-panel">
    <div class="stat-card stat-waiting">
      <span class="stat-icon">⏳</span>
      <span class="stat-num">{stats.waiting}</span>
      <span class="stat-label">En Espera</span>
    </div>
    <div class="stat-card stat-serving">
      <span class="stat-icon">🩺</span>
      <span class="stat-num">{stats.serving}</span>
      <span class="stat-label">Atendiendo</span>
    </div>
    <div class="stat-card stat-done">
      <span class="stat-icon">✅</span>
      <span class="stat-num">{stats.done}</span>
      <span class="stat-label">Completados</span>
    </div>
    <div class="stat-card stat-noshow">
      <span class="stat-icon">🚫</span>
      <span class="stat-num">{stats.noShow}</span>
      <span class="stat-label">No-Show</span>
    </div>
  </div>

  <!-- Activity Log -->
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
</div>

{/if}

<!-- ═══════ TRANSFER MODAL ═══════ -->
<Modal bind:open={showTransferModal} title="Transferir Turno" on:close={() => showTransferModal = false}>
  <form on:submit|preventDefault={handleTransfer} class="modal-form">
    <p class="text-sm muted mb-16">
      Transferir turno <strong>{calledTicket?.code}</strong> a otra cola de servicio.
      El turno actual será marcado como transferido y se generará un nuevo turno en la cola destino.
    </p>

    <div class="form-group">
      <label class="form-label" for="transfer-prefix">Servicio de Destino</label>
      <select id="transfer-prefix" class="input" bind:value={transferToPrefix} required>
        <option value="" disabled>Seleccionar servicio...</option>
        {#each queueSettings as qs}
          {#if qs.prefix !== stationPrefix && qs.service_name}
            <option value={qs.prefix}>{qs.service_name} ({qs.prefix})</option>
          {/if}
        {/each}
      </select>
    </div>

    <div class="form-group mt-16">
      <label class="form-label" for="transfer-notes">Notas (Opcional)</label>
      <textarea id="transfer-notes" class="input text-area" bind:value={transferReason} placeholder="Razón de la transferencia..."></textarea>
    </div>

    <div class="modal-footer mt-16" style="display:flex; justify-content:flex-end; gap:8px;">
      <button type="button" class="btn btn-ghost" on:click={() => showTransferModal = false}>Cancelar</button>
      <button type="submit" class="btn btn-primary" disabled={submittingTransfer || !transferToPrefix}>
        {submittingTransfer ? 'Transfiriendo...' : 'Transferir Turno'}
      </button>
    </div>
  </form>
</Modal>

<!-- ═══════ NO-SHOW REQUEUE MODAL ═══════ -->
<Modal bind:open={showNoShowModal} title="Turnos No-Show — Reinsertar" size="lg" on:close={() => showNoShowModal = false}>
  {#if loadingNoShowList}
    <p class="text-sm muted">Cargando…</p>
  {:else if noShowList.length === 0}
    <p class="text-sm muted">No hay turnos marcados como No-Show hoy para esta cola.</p>
  {:else}
    <div class="noshow-list">
      {#each noShowList as t (t.ticket_id)}
        <div class="noshow-row">
          <div class="noshow-info">
            <strong class="noshow-code">{t.code}</strong>
            <span class="noshow-meta">No-Show {timeAgo(t.called_at)} · brecha: {t.gap} turno(s)</span>
          </div>
          <button
            class="btn btn-primary btn-sm"
            disabled={!t.eligible || requeuingTicketId === t.ticket_id}
            title={t.eligible ? 'Reinsertar en la cola' : `Bloqueado: ya se llamaron ${t.gap} turnos después (límite excedido)`}
            on:click={() => requeueTicket(t.ticket_id)}
          >
            {requeuingTicketId === t.ticket_id ? 'Reinsertando…' : 'Reinsertar'}
          </button>
        </div>
      {/each}
    </div>
  {/if}
</Modal>

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

/* ── Ticket Panel ── */
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
.tp-module {
  margin-top: 12px;
  font-size: .9rem;
  color: var(--text-muted);
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

/* ── Controls Panel ── */
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

/* ═══════ NO-SHOW REQUEUE MODAL ═══════ */
.noshow-list { display: flex; flex-direction: column; gap: 8px; max-height: 400px; overflow-y: auto; }
.noshow-row {
  display: flex; align-items: center; justify-content: space-between; gap: 12px;
  padding: 10px 14px; border: 1px solid var(--border); border-radius: var(--radius-sm);
}
.noshow-info { display: flex; flex-direction: column; gap: 2px; }
.noshow-code { font-size: 1rem; color: var(--text); }
.noshow-meta { font-size: .75rem; color: var(--text-muted); }

/* ═══════ BOTTOM ROW ═══════ */
.bottom-row {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 20px;
}

/* Stats */
.stats-panel {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;
}
.stat-card {
  background: white;
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: 16px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  min-width: 100px;
  box-shadow: var(--shadow-sm);
}
.stat-icon { font-size: 1.25rem; }
.stat-num {
  font-size: 1.75rem;
  font-weight: 800;
  line-height: 1;
}
.stat-label {
  font-size: .7rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: .05em;
  color: var(--text-muted);
}
.stat-waiting .stat-num { color: #f59e0b; }
.stat-serving .stat-num { color: #22c55e; }
.stat-done .stat-num { color: var(--primary); }
.stat-noshow .stat-num { color: #ef4444; }

/* Activity */
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

/* ═══════ RESPONSIVE ═══════ */
@media (max-width: 900px) {
  .station-layout {
    grid-template-columns: 1fr;
  }
  .bottom-row {
    grid-template-columns: 1fr;
  }
  .stats-panel {
    grid-template-columns: repeat(2, 1fr);
  }
  .cp-buttons-sm {
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
