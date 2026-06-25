<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { toasts } from '$lib/stores.js';
  import { slide } from 'svelte/transition';

  let currentTab = 'run'; // 'run' | 'history'
  
  // -- RUN TAB --
  let opDateStr = new Date().toISOString().split('T')[0];
  let loadingPreview = false;
  let loadingRun = false;
  let previewData = null; // Array of tickets
  let showConfirm = false;
  
  // -- HISTORY TAB --
  let runs = [];
  let loadingHistory = false;

  async function loadPreview() {
    if (!opDateStr) return toasts.error('Debes seleccionar una fecha operativa');
    
    loadingPreview = true;
    previewData = null;
    showConfirm = false;
    
    try {
      const res = await api.post('/api/admin/daily-close/preview', { operational_date: opDateStr });
      previewData = res.data || [];
      if (previewData.length === 0) {
        toasts.warn('No hay tickets pendientes para la fecha seleccionada');
      }
    } catch (e) {
      toasts.error('Error cargando la vista previa: ' + e.message);
    } finally {
      loadingPreview = false;
    }
  }

  async function executeRun() {
    loadingRun = true;
    try {
      const res = await api.post('/api/admin/daily-close/run', { operational_date: opDateStr });
      const closedTickets = res.data?.length || 0;
      toasts.success(`Cierre completado. ${closedTickets} tickets expirados.`);
      
      previewData = null;
      showConfirm = false;
      
      // If we go to history, we'll want it refreshed
      await loadHistory();
    } catch (e) {
      toasts.error('Error ejecutando el cierre: ' + e.message);
    } finally {
      loadingRun = false;
    }
  }

  async function loadHistory() {
    loadingHistory = true;
    try {
      const res = await api.get('/api/admin/daily-close/runs');
      runs = res.data || [];
    } catch (e) {
      toasts.error('Error cargando el historial: ' + e.message);
    } finally {
      loadingHistory = false;
    }
  }

  onMount(() => {
    loadHistory();
  });
</script>

<div class="page-container">
  <div class="header">
    <div class="title-section">
      <h1>Daily Close</h1>
      <p class="subtitle">Cierre manual de turnos pendientes</p>
    </div>
  </div>

  <div class="tabs">
    <button class="tab-btn" class:active={currentTab === 'run'} on:click={() => currentTab = 'run'}>
      Ejecutar Cierre 
    </button>
    <button class="tab-btn" class:active={currentTab === 'history'} on:click={() => currentTab = 'history'}>
      Historial
    </button>
  </div>

  {#if currentTab === 'run'}
    <div class="card p-lg" in:slide>
      <div class="alert alert-info">
        <strong>Información:</strong> Esta herramienta cerrará (pasará a estado EXPIRADO) a los tickets en estado <em>EN COLA</em> o <em>LLAMADO</em> que hayan quedado abiertos de días anteriores, para aquellas colas configuradas como <code>DAILY_RESET</code>. Los tickets en atención o ya finalizados permanecerán intactos.
      </div>
      
      <div class="run-form">
        <div class="form-group w-max-300">
          <label for="opDate">Fecha Operativa</label>
          <input type="date" id="opDate" class="input" bind:value={opDateStr} />
          <p class="help-text">Se evaluarán tickets creados <strong>antes</strong> de esta fecha.</p>
        </div>
        
        <div class="form-actions">
          <button class="btn btn-secondary" on:click={loadPreview} disabled={loadingPreview || loadingRun}>
            {#if loadingPreview}⏳ Cargando...{:else}Ver Preview de Candidatos{/if}
          </button>
        </div>
      </div>

      {#if previewData !== null}
        <div class="preview-section" transition:slide>
          <div class="preview-header">
            <h3>Candidatos al Cierre ({previewData?.length ?? 0})</h3>
            {#if (previewData?.length ?? 0) > 0}
              <button class="btn btn-danger" on:click={() => showConfirm = true} disabled={loadingRun}>
                Ejecutar Cierre Manual
              </button>
            {/if}
          </div>

          {#if showConfirm}
            <div class="alert alert-warning confirm-box" transition:slide>
              <strong>⚠ Atención:</strong> Estás a punto de expirar {previewData?.length ?? 0} tickets. Esta acción quedará registrada en el sistema de auditoría bajo tu usuario. ¿Deseas proceder?
              <div class="confirm-actions mt-sm">
                <button class="btn btn-secondary btn-sm" on:click={() => showConfirm = false} disabled={loadingRun}>Cancelar</button>
                <button class="btn btn-danger btn-sm" on:click={executeRun} disabled={loadingRun}>
                  {#if loadingRun}⏳ Ejecutando...{:else}Sí, Cerrar Tickets{/if}
                </button>
              </div>
            </div>
          {/if}

          {#if (previewData?.length ?? 0) > 0}
            <div class="table-container mt-md">
              <table class="table">
                <thead>
                  <tr>
                    <th>Código</th>
                    <th>Servicio (Prefijo)</th>
                    <th>Estado Actual</th>
                    <th>Fecha Ticket</th>
                  </tr>
                </thead>
                <tbody>
                  {#each previewData as t}
                    <tr>
                      <td class="font-bold">{t.code}</td>
                      <td><span class="badge badge-primary">{t.prefix}</span></td>
                      <td><span class="badge badge-warning">{t.out_old_status}</span> -> <span class="badge badge-danger">EXPIRADO</span></td>
                      <td class="muted">{new Date(t.out_ticket_date).toLocaleDateString()}</td>
                    </tr>
                  {/each}
                </tbody>
              </table>
            </div>
          {:else}
            <div class="empty-state mt-md">
              <div class="empty-icon">✓</div>
              <p>No se encontraron tickets pendientes para cerrar antes del {opDateStr}.</p>
            </div>
          {/if}
        </div>
      {/if}
    </div>
  {/if}

  {#if currentTab === 'history'}
    <div class="card p-lg" in:slide>
      <div class="header-with-actions mb-md">
        <h3>Registro Diario de Cierres</h3>
        <button class="btn btn-secondary btn-sm" on:click={loadHistory} disabled={loadingHistory}>
          ↻ Refrescar
        </button>
      </div>

      {#if loadingHistory}
        <div class="text-center py-lg muted">Cargando historial...</div>
      {:else if runs.length > 0}
        <div class="table-container">
          <table class="table">
            <thead>
              <tr>
                <th>ID</th>
                <th>Fecha Operativa</th>
                <th>Modo</th>
                <th>Cerrados</th>
                <th>Ejecutado Por</th>
                <th>Fecha Ejecución</th>
              </tr>
            </thead>
            <tbody>
              {#each runs as r}
                <tr>
                  <td class="muted">#{r.run_id}</td>
                  <td class="font-bold">{new Date(r.operational_date).toLocaleDateString()}</td>
                  <td>
                    <span class="badge {r.run_mode === 'MANUAL' ? 'badge-primary' : 'badge-success'}">
                      {r.run_mode}
                    </span>
                  </td>
                  <td>{r.tickets_closed} tickets</td>
                  <td>{r.executed_by_name || 'Sistema'}</td>
                  <td class="muted text-sm">{new Date(r.started_at).toLocaleString()}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {:else}
        <div class="empty-state">
           <div class="empty-icon">📝</div>
           <p>No hay historial de cierres diarios registrados.</p>
        </div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .tabs {
    display: flex; gap: 4px; margin-bottom: 24px;
    border-bottom: 2px solid var(--border);
  }
  .tab-btn {
    padding: 12px 24px; border: none; background: transparent;
    font-size: 0.95rem; font-weight: 600; color: var(--text-muted); cursor: pointer;
    border-bottom: 2px solid transparent; margin-bottom: -2px; transition: all 0.2s;
  }
  .tab-btn:hover { color: var(--text); }
  .tab-btn.active { color: var(--primary); border-bottom-color: var(--primary); }
  
  .run-form {
    display: flex; align-items: flex-end; gap: 16px; margin: 24px 0;
    padding-bottom: 24px; border-bottom: 1px dashed var(--border);
  }
  .w-max-300 { max-width: 300px; width: 100%; }
  
  .preview-section { margin-top: 24px; }
  .preview-header { 
    display: flex; justify-content: space-between; align-items: center; 
  }
  .preview-header h3 { margin: 0; }
  
  .confirm-box {
    margin-top: 16px; border: 1px solid #f59e0b; background: #fffbeb;
  }
  .confirm-actions { display: flex; gap: 8px; }
  
  .empty-state {
    padding: 48px 24px; text-align: center; color: var(--text-muted);
  }
  .empty-icon {
    font-size: 3rem; margin-bottom: 16px; opacity: 0.5;
  }
  
  /* Utilities */
  .mt-sm { margin-top: 8px; }
  .mt-md { margin-top: 16px; }
  .mb-md { margin-bottom: 16px; }
  .p-lg { padding: 24px; }
  .py-lg { padding: 24px 0; }
  .text-center { text-align: center; }
  .header-with-actions { display: flex; justify-content: space-between; align-items: center; }
  
  .alert {
    padding: 16px; border-radius: var(--radius-md); font-size: 0.95rem; line-height: 1.5;
  }
  .alert-info { background: #eff6ff; color: #1e3a8a; border: 1px solid #bfdbfe; }
  .alert-warning { background: #fffcf0; color: #b45309; }
</style>
