<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';

  let data = [];
  let loading = true;
  let filterDate = new Date().toISOString().split('T')[0];

  async function loadData() {
    loading = true;
    try {
      const res = await api.get(`/api/admin/reports/waiting-time?date=${filterDate}`);
      data = res?.data ?? res;
    } catch (e) {
      toasts.error(e.message || 'Failed to load report');
    } finally {
      loading = false;
    }
  }

  onMount(loadData);
</script>

<svelte:head>
  <title>Waiting Time Report — Admin</title>
</svelte:head>

<div class="page-header">
  <div>
    <div class="breadcrumb"><a href="/admin/reports">← Back to Reports</a></div>
    <h2 class="page-title">Waiting Time Analytics</h2>
    <p class="page-subtitle">Medición del tiempo que tarda un paciente (desde la emisión hasta su llamado).</p>
  </div>
</div>

<div class="card mb-20">
  <div class="card-body filter-row">
    <div class="form-group">
      <label class="form-label text-sm" for="filterDate">Fecha</label>
      <input type="date" id="filterDate" class="input" bind:value={filterDate} on:change={loadData} />
    </div>
    <div class="form-group" style="align-self: flex-end; margin-bottom: 2px;">
      <button class="btn btn-ghost" on:click={loadData}>↻ Refresh</button>
    </div>
  </div>
</div>

{#if loading}
  <div class="empty-state"><div class="spinner"></div> Calculando…</div>
{:else if data.length === 0}
  <div class="empty-state">
    <span class="icon">⏳</span>
    <p>No hay datos de espera cerrados para este día.</p>
  </div>
{:else}
  <div class="card">
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Área / Módulo</th>
            <th>Tickets Atendidos</th>
            <th>Promedio (min)</th>
            <th>Mínimo (min)</th>
            <th>Máximo (min)</th>
          </tr>
        </thead>
        <tbody>
          {#each data as row}
            <tr>
              <td><strong>{row.module_name || row.station_name || 'Desconocido'}</strong></td>
              <td>{row.total_tickets}</td>
              <td><span class="badge badge-warning">{row.avg_wait_min} min</span></td>
              <td class="muted">{row.min_wait_min} min</td>
              <td class="muted">{row.max_wait_min} min</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </div>
{/if}

<style>
  .breadcrumb { margin-bottom: 12px; }
  .breadcrumb a { color: var(--muted); text-decoration: none; font-size: 0.9rem; }
  .breadcrumb a:hover { color: var(--primary); text-decoration: underline; }
  .mb-20 { margin-bottom: 20px; }
  .filter-row { display: flex; gap: 16px; align-items: flex-end; }
  .form-group { min-width: 200px; }
  .spinner { width: 28px; height: 28px; border: 3px solid var(--border); border-top-color: var(--primary); border-radius: 50%; animation: spin .7s linear infinite; margin: 0 auto 16px; }
  @keyframes spin { to { transform: rotate(360deg); } }
</style>
