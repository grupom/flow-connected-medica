<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';

  let tickets = [];
  let loading = true;
  let filterDate = new Date().toISOString().split('T')[0];
  let filterStatus = '';
  
  let pagination = {
    limit: 50,
    offset: 0,
    total: 0
  };

  async function loadReports() {
    loading = true;
    try {
      const qs = new URLSearchParams();
      if (filterDate) qs.set('date', filterDate);
      if (filterStatus) qs.set('status', filterStatus);
      qs.set('limit', pagination.limit);
      qs.set('offset', pagination.offset);

      const res = await api.get(`/api/admin/reports/tickets?${qs.toString()}`);
      const payload = res?.data ? res : { data: res, meta: { total: res.length } };
      
      tickets = payload.data || [];
      pagination.total = payload.meta?.total || 0;
    } catch (e) {
      toasts.error(e.message || 'Failed to load reports');
    } finally {
      loading = false;
    }
  }

  function handleFilter() {
    pagination.offset = 0;
    loadReports();
  }

  function prevPage() {
    if (pagination.offset > 0) {
      pagination.offset -= pagination.limit;
      loadReports();
    }
  }

  function nextPage() {
    if (pagination.offset + pagination.limit < pagination.total) {
      pagination.offset += pagination.limit;
      loadReports();
    }
  }

  onMount(() => loadReports());
</script>

<svelte:head>
  <title>Reports — Admin</title>
</svelte:head>

<div class="page-header">
  <div>
    <div class="breadcrumb"><a href="/admin/reports">← Back to Reports</a></div>
    <h2 class="page-title">Ticket History</h2>
    <p class="page-subtitle">View daily queue logs, wait times, and service times.</p>
  </div>
</div>

<div class="card filters-card mb-20">
  <div class="card-body">
    <div class="filter-row">
      <div class="form-group">
        <label class="form-label text-sm" for="filterDate">Date</label>
        <input type="date" id="filterDate" class="input" bind:value={filterDate} on:change={handleFilter} />
      </div>
      <div class="form-group">
        <label class="form-label text-sm" for="filterStatus">Status</label>
        <select id="filterStatus" class="input" bind:value={filterStatus} on:change={handleFilter}>
          <option value="">All Statuses</option>
          <option value="EN_COLA">Waiting</option>
          <option value="LLAMADO">Called</option>
          <option value="EN_ATENCION">Serving</option>
          <option value="FINALIZADO">Completed</option>
          <option value="NO_SHOW">No-Show</option>
          <option value="CANCELADO">Cancelled</option>
          <option value="TRANSFERIDO">Transferred</option>
        </select>
      </div>
      <div class="form-group" style="align-self: flex-end; margin-bottom: 2px;">
        <button class="btn btn-ghost" on:click={handleFilter}>↻ Refresh</button>
      </div>
    </div>
  </div>
</div>

{#if loading}
  <div class="empty-state"><div class="spinner"></div> Loading reports…</div>
{:else if tickets.length === 0}
  <div class="empty-state">
    <span class="icon">📊</span>
    <p>No tickets found for these filters.</p>
  </div>
{:else}
  <div class="card">
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Ticket</th>
            <th>Status</th>
            <th>Station</th>
            <th>Created</th>
            <th>Wait Time</th>
            <th>Service Time</th>
          </tr>
        </thead>
        <tbody>
          {#each tickets as t}
            <tr>
              <td><strong>{t.ticket_number}</strong></td>
              <td>
                <span class="badge {
                  t.status_nice === 'Waiting' ? 'badge-warning' :
                  t.status_nice === 'Serving' ? 'badge-success' :
                  t.status_nice === 'Done' ? 'badge-primary' :
                  t.status_nice === 'Called' ? 'badge-purple' : 'badge-gray'
                }">{t.status_nice}</span>
              </td>
              <td>{t.station_name || '—'}</td>
              <td class="muted text-sm">{new Date(t.created_at).toLocaleTimeString()}</td>
              <td class="muted">
                {#if t.wait_time_mins !== null}
                  {t.wait_time_mins} min
                {:else}
                  —
                {/if}
              </td>
              <td class="muted">
                {#if t.service_time_mins !== null}
                  {t.service_time_mins} min
                {:else}
                  —
                {/if}
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
    
    <div class="pagination">
      <span class="muted text-sm">
        Showing {pagination.offset + 1} to {Math.min(pagination.offset + pagination.limit, pagination.total)} of {pagination.total}
      </span>
      <div class="page-controls">
        <button class="btn btn-sm btn-ghost" on:click={prevPage} disabled={pagination.offset === 0}>Prev</button>
        <button class="btn btn-sm btn-ghost" on:click={nextPage} disabled={pagination.offset + pagination.limit >= pagination.total}>Next</button>
      </div>
    </div>
  </div>
{/if}

<style>
.breadcrumb { margin-bottom: 12px; }
.breadcrumb a { color: var(--muted); text-decoration: none; font-size: 0.9rem; }
.breadcrumb a:hover { color: var(--primary); text-decoration: underline; }
.mb-20 { margin-bottom: 20px; }

.filter-row {
  display: flex;
  gap: 16px;
  align-items: flex-end;
  flex-wrap: wrap;
}

.filter-row .form-group {
  min-width: 180px;
  flex: 1;
}

.pagination {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 16px;
  border-top: 1px solid var(--border);
}

.page-controls {
  display: flex;
  gap: 8px;
}

.spinner {
  width: 28px; height: 28px;
  border: 3px solid var(--border);
  border-top-color: var(--primary);
  border-radius: 50%;
  animation: spin .7s linear infinite;
  margin: 0 auto 16px;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
