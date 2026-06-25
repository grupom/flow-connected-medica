<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';

  let data = [];
  let loading = true;
  // Default to 7 days config
  let startDate = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
  let endDate = new Date().toISOString().split('T')[0];

  async function loadData() {
    loading = true;
    try {
      const qs = new URLSearchParams({ start: startDate, end: endDate }).toString();
      const res = await api.get(`/api/admin/reports/congestion-demand?${qs}`);
      data = res?.data ?? res;
    } catch (e) {
      toasts.error(e.message || 'Error loading demand data');
    } finally {
      loading = false;
    }
  }

  onMount(loadData);
</script>

<svelte:head>
  <title>Congestion & Demand — Admin</title>
</svelte:head>

<div class="page-header">
  <div>
    <div class="breadcrumb"><a href="/admin/reports">← Back to Reports</a></div>
    <h2 class="page-title">Congestion & Demand</h2>
    <p class="page-subtitle">Análisis del volumen de pacientes entrantes por hora / día para detectar picos operativos.</p>
  </div>
</div>

<div class="card mb-20">
  <div class="card-body filter-row">
    <div class="form-group">
      <label class="form-label text-sm" for="startDate">Desde</label>
      <input type="date" id="startDate" class="input" bind:value={startDate} />
    </div>
    <div class="form-group">
      <label class="form-label text-sm" for="endDate">Hasta</label>
      <input type="date" id="endDate" class="input" bind:value={endDate} />
    </div>
    <div class="form-group" style="align-self: flex-end; margin-bottom: 2px;">
      <button class="btn btn-ghost" on:click={loadData}>↻ Cargar</button>
    </div>
  </div>
</div>

{#if loading}
  <div class="empty-state"><div class="spinner"></div></div>
{:else if data.length === 0}
  <div class="empty-state">
    <span class="icon">📉</span>
    <p>No hay registros en este rango de fechas.</p>
  </div>
{:else}
  <div class="dash-row">
    <!-- Summary KPI style -->
    <div class="card">
       <div class="card-body" style="display: flex; gap: 40px; justify-content: space-around;">
         <div class="kpi-mini text-center">
            <span class="muted text-sm">Rango Analizado</span>
            <div style="font-size: 1.2rem; font-weight: bold; margin-top: 8px;">{data.reduce((sum, d) => sum + parseInt(d.total_tickets), 0)} Tickets</div>
         </div>
       </div>
    </div>
  </div>

  <div class="card" style="margin-top: 20px;">
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Día / Fecha</th>
            <th>Hora Principal</th>
            <th class="text-right">Volumen Emisión</th>
          </tr>
        </thead>
        <tbody>
          {#each data as row}
            <tr>
              <td><strong>{row.log_date}</strong></td>
              <td><span class="badge badge-gray">{row.log_hour}:00</span></td>
              <td class="text-right">
                <span class="badge {row.total_tickets > 20 ? 'badge-danger' : 'badge-primary'}">
                  {row.total_tickets} tickets
                </span>
              </td>
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
  .form-group { min-width: 150px; }
  .spinner { width: 28px; height: 28px; border: 3px solid var(--border); border-top-color: var(--primary); border-radius: 50%; animation: spin .7s linear infinite; margin: 0 auto 16px; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .text-right { text-align: right; }
  .text-center { text-align: center; }
</style>
