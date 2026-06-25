<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { auth } from '$lib/auth.js';
  import { toasts } from '$lib/stores.js';
  import KpiCard from '$lib/components/KpiCard.svelte';

  let stats = { waiting: 0, serving: 0, done: 0, noShow: 0 };
  let recentTickets = [];
  let stations = [];
  let loading = true;

  $: userRoles = $auth.user?.role_codes || [];
  $: isAdmin = userRoles.includes('ADMIN');

  async function loadDashboard() {
    loading = true;
    try {
      // Get real metrics
      try {
        const res = await api.get('/api/admin/metrics');
        const m = res?.data ?? res;
        if (m) {
          stats = m.stats;
          recentTickets = m.tickets;
        }
      } catch (e) {
        console.error('Failed to load metrics:', e);
      }
    } catch (e) {
      toasts.error(e.message || 'Failed to load dashboard');
    } finally {
      loading = false;
    }
  }

  onMount(loadDashboard);
</script>

<div class="dashboard">
  <!-- KPI Grid -->
  <div class="kpi-grid">
    <KpiCard label="En Espera"  value={stats.waiting}  color="warning" icon="⏳" />
    <KpiCard label="Atendiendo" value={stats.serving}  color="success" icon="🔔" />
    <KpiCard label="Completados" value={stats.done}     color="primary" icon="✅" />
    <KpiCard label="No-Show"   value={stats.noShow}   color="danger"  icon="🚫" />
  </div>

  <div class="dash-row">
    <!-- Recent Tickets -->
    <div class="card dash-card flex-2">
      <div class="card-body">
        <div class="section-header">
          <h3>Actividad Reciente</h3>
          <button class="btn btn-ghost btn-sm" on:click={loadDashboard}>↻ Refresh</button>
        </div>

        {#if loading}
          <div class="empty-state"><div class="spinner"></div></div>
        {:else if recentTickets.length === 0}
          <div class="empty-state">
            <span class="icon">🎫</span>
            <p>No hay actividad aún. Emita turnos para comenzar.</p>
          </div>
        {:else}
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>Módulo</th>
                  <th>Status</th>
                  <th>Hora</th>
                </tr>
              </thead>
              <tbody>
                {#each recentTickets as t}
                  <tr>
                    <td><strong>{t.ticket_number}</strong></td>
                    <td>{t.module_name ?? t.station_name ?? '—'}</td>
                    <td>
                      <span class="badge {t.status === 'serving' ? 'badge-success' :
                            t.status === 'waiting'   ? 'badge-warning' :
                            t.status === 'done'      ? 'badge-primary' : 'badge-danger'}">
                        {t.status}
                      </span>
                    </td>
                    <td class="muted text-sm">
                      {t.ended_at ? new Date(t.ended_at).toLocaleTimeString() : t.called_at ? new Date(t.called_at).toLocaleTimeString() : '—'}
                    </td>
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        {/if}
      </div>
    </div>
  </div>
</div>

<style>
.dashboard { display: flex; flex-direction: column; gap: 24px; }

.kpi-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 16px;
}

.dash-row {
  display: flex;
  flex-direction: column;
  gap: 20px;
}
.dash-card { width: 100%; }

.section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 16px;
}

.spinner {
  width: 28px; height: 28px;
  border: 3px solid var(--border);
  border-top-color: var(--primary);
  border-radius: 50%;
  animation: spin .7s linear infinite;
  margin: 24px auto;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
