<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';

  let data = [];
  let loading = true;
  let filterDate = new Date().toISOString().split('T')[0];
  let groupBy = 'module'; // 'module' | 'station'

  async function loadData() {
    loading = true;
    try {
      const res = await api.get(`/api/admin/reports/tickets-by-station-area?date=${filterDate}&groupBy=${groupBy}`);
      data = res?.data ?? res;
    } catch (e) {
      toasts.error(e.message || 'Error loading report');
    } finally {
      loading = false;
    }
  }

  onMount(loadData);
</script>

<svelte:head>
  <title>Tickets by Area / Station — Admin</title>
</svelte:head>

<div class="page-header">
  <div>
    <div class="breadcrumb"><a href="/admin/reports">← Back to Reports</a></div>
    <h2 class="page-title">Tickets by Area / Station</h2>
    <p class="page-subtitle">Desglose de la operatividad clasificada por áreas funcionales o por estaciones de trabajo directas.</p>
  </div>
</div>

<div class="card mb-20">
  <div class="card-body filter-row">
    <div class="form-group">
      <label class="form-label text-sm" for="filterDate">Fecha</label>
      <input type="date" id="filterDate" class="input" bind:value={filterDate} />
    </div>
    <div class="form-group">
      <label class="form-label text-sm" for="groupBy">Agrupar Por</label>
      <select id="groupBy" class="input" bind:value={groupBy}>
        <option value="module">Módulo / Área Médica</option>
        <option value="station">Estación (Taquillas de atención)</option>
      </select>
    </div>
    <div class="form-group" style="align-self: flex-end; margin-bottom: 2px;">
      <button class="btn btn-ghost" on:click={loadData}>↻ Actualizar</button>
    </div>
  </div>
</div>

{#if loading}
  <div class="empty-state"><div class="spinner"></div></div>
{:else if data.length === 0}
  <div class="empty-state">
    <span class="icon">🏢</span>
    <p>No hay operación registrada para este día.</p>
  </div>
{:else}
  <div class="card">
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>{groupBy === 'module' ? 'Área / Módulo' : 'Estación de Trabajo'}</th>
            <th class="text-right">Completados ✅</th>
            <th class="text-right">En Espera ⏳</th>
            <th class="text-right">No Show 🚫</th>
            <th class="text-right">Total Emitidos 🎫</th>
          </tr>
        </thead>
        <tbody>
          {#each data as row}
            <tr>
              <td><strong>{row.group_name || 'Desconocido'}</strong></td>
              <td class="text-right"><span class="badge badge-success">{row.done_count}</span></td>
              <td class="text-right"><span class="badge badge-warning">{row.waiting_count}</span></td>
              <td class="text-right"><span class="badge badge-danger">{row.noshow_count}</span></td>
              <td class="text-right" style="font-weight: 700;">{row.total_issued}</td>
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
  .text-right { text-align: right; }
</style>
