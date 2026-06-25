<script>
  import { onMount, onDestroy } from 'svelte';
  import { api } from '$lib/api.js';
  import { auth } from '$lib/auth.js';
  import { toasts } from '$lib/stores.js';
  import { fade, slide, scale } from 'svelte/transition';
  import { printTicket } from '$lib/printing/printTicket.js';

  let services = [];
  let waitingCounts = {};
  let loading = true;
  let issuing = null;
  let lastTicket = null;
  let pollInterval;

  onMount(async () => {
    await loadInitialData();
    pollInterval = setInterval(loadMetrics, 5000); 
  });

  onDestroy(() => {
    if (pollInterval) clearInterval(pollInterval);
  });

  async function loadInitialData() {
    loading = true;
    try {
      const res = await api.get('/api/admin/queue-settings');
      // Show: regular walkin prefixes + priority prefixes (staff-only, never kiosk)
      // Exclude: non-walkin, non-priority prefixes (appointment-only)
      services = (res.data || []).filter(s => s.service_name && (s.allow_walkins || s.is_priority_for));
      await loadMetrics();
    } catch (e) {
      toasts.error('Error cargando servicios: ' + e.message);
    } finally {
      loading = false;
    }
  }

  async function loadMetrics() {
    try {
      const res = await api.get('/api/admin/metrics');
      waitingCounts = res.data?.stats?.waitingByPrefix || {};
    } catch (e) {
      // Slient fail for background polling
    }
  }

  async function generateTicket(service) {
    if (issuing) return;
    issuing = service.prefix;
    try {
      // Priority prefixes must NOT be walkin (kiosk-style) — staff-issued only
      const res = await api.post('/api/queue/create-ticket', {
        prefix:    service.prefix,
        is_walkin: service.is_priority_for ? false : true,
        created_by: $auth.user?.user_id,
      });
      
      const ticketData = res.data || res;
      
      lastTicket = {
        code: ticketData.code,
        serviceName: service.service_name,
        timestamp: new Date().toLocaleTimeString('es-DO', { hour: '2-digit', minute: '2-digit', second: '2-digit' })
      };
      
      toasts.success(`Turno ${ticketData.code} generado`);
      
      // Print the thermal ticket
      if (ticketData.code) {
          try {
              await printTicket({
                  code: ticketData.code,
                  prefix: ticketData.prefix,
                  service_name: service.service_name,
                  tck_number: ticketData.tck_number
              });
          } catch (printErr) {
              toasts.error(`Turno emitido pero falló al imprimir: ${printErr.message}`);
          }
      }

      await loadMetrics(); // update counts immediately
    } catch (e) {
      toasts.error('Error generando turno: ' + e.message);
    } finally {
      issuing = null;
    }
  }
</script>

<div class="front-desk-container">

  {#if loading}
    <div class="loading-state">
      <div class="spinner"></div>
      <p>Cargando servicios...</p>
    </div>
  {:else}
    <div class="services-grid">
      {#each services as svc}
        <button
          class="service-card {svc.is_priority_for ? 'service-card--priority' : ''}"
          on:click={() => generateTicket(svc)}
          disabled={issuing === svc.prefix}
        >
          {#if svc.is_priority_for}
            <div class="priority-ribbon">⚡ PRIORIDAD</div>
          {/if}

          <div class="service-icon">{svc.icon || '📝'}</div>
          <div class="service-content">
            <span class="service-title">{svc.service_name}</span>
            <span class="service-prefix">Cola: {svc.prefix}</span>
            {#if svc.is_priority_for}
              <span class="priority-sub">Embarazadas · Adultos mayores</span>
            {/if}
          </div>

          <div class="service-status">
            {#if waitingCounts[svc.prefix]}
               <div class="badge waiting" in:scale>
                 {waitingCounts[svc.prefix]} en espera
               </div>
            {:else}
               <div class="badge empty">Libre</div>
            {/if}
          </div>

          {#if issuing === svc.prefix}
             <div class="card-loader"></div>
          {/if}

          <div class="action-hint">
            {svc.is_priority_for ? 'Emitir Turno Priority →' : 'Emitir Turno →'}
          </div>
        </button>
      {/each}
    </div>

    {#if lastTicket}
      <div class="last-ticket-overlay" transition:fade>
        <div class="ticket-modal" in:scale={{ duration: 300, start: 0.9 }}>
          <div class="modal-header">
             <span class="badge-success">EMITIDO</span>
             <button class="close-btn" on:click={() => lastTicket = null}>✕</button>
          </div>
          
          <div class="ticket-body">
            <span class="ticket-label">SU TURNO ES</span>
            <h2 class="ticket-number">{lastTicket.code}</h2>
            <div class="ticket-footer">
              <span class="svc-name">{lastTicket.serviceName}</span>
              <span class="timestamp">{lastTicket.timestamp}</span>
            </div>
          </div>
          
          <div class="modal-actions">
            <button class="btn btn-primary btn-block" on:click={() => lastTicket = null}>LISTO</button>
          </div>
        </div>
      </div>
    {/if}
  {/if}
</div>

<style>
  .front-desk-container {
    max-width: 1100px;
    margin: 0 auto;
    padding: 32px 20px;
    min-height: calc(100vh - 100px);
  }

  .services-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 20px;
  }

  .service-card {
    background: white;
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    padding: 20px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    cursor: pointer;
    transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    position: relative;
    overflow: hidden;
    box-shadow: var(--shadow-sm);
    text-align: center;
  }

  .service-card:hover:not(:disabled) {
    border-color: var(--primary);
    transform: translateY(-4px);
    box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);
  }

  /* Priority card */
  .service-card--priority {
    border-color: #f59e0b;
    background: linear-gradient(135deg, #fffbeb 0%, #fff 60%);
  }
  .service-card--priority:hover:not(:disabled) {
    border-color: #d97706;
    box-shadow: 0 20px 25px -5px rgba(245, 158, 11, 0.2), 0 10px 10px -5px rgba(245, 158, 11, 0.1);
  }
  .priority-ribbon {
    position: absolute;
    top: 10px;
    right: -1px;
    background: #f59e0b;
    color: #fff;
    font-size: 0.65rem;
    font-weight: 800;
    letter-spacing: 0.5px;
    padding: 3px 10px;
    border-radius: 4px 0 0 4px;
  }
  .priority-sub {
    font-size: 0.72rem;
    color: #b45309;
    font-weight: 600;
    margin-top: 2px;
  }

  .service-card:disabled {
    opacity: 0.6;
    cursor: default;
  }

  .service-icon {
    font-size: 2.5rem;
    width: 64px;
    height: 64px;
    background: #f8fafc;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 50%;
    transition: transform 0.3s ease;
  }

  .service-card:hover .service-icon {
    transform: scale(1.1);
  }

  .service-content {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .service-title {
    font-size: 1.25rem;
    font-weight: 700;
    color: var(--text);
  }

  .service-prefix {
    font-size: 0.9rem;
    color: var(--text-muted);
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .service-status {
    min-height: 28px;
  }

  .badge {
    padding: 4px 10px;
    border-radius: 20px;
    font-size: 0.75rem;
    font-weight: 600;
  }

  .badge.waiting {
    background: #fef2f2;
    color: #ef4444;
  }

  .badge.empty {
    background: #f0fdf4;
    color: #16a34a;
  }

  .action-hint {
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--primary);
    margin-top: 4px;
    opacity: 0;
    transition: opacity 0.2s;
  }

  .service-card:hover .action-hint {
    opacity: 1;
  }

  .card-loader {
    position: absolute;
    bottom: 0;
    left: 0;
    height: 4px;
    background: var(--primary);
    width: 100%;
    animation: bar-loading 1.2s infinite ease-in-out;
  }

  @keyframes bar-loading {
    0% { transform: translateX(-100%); }
    100% { transform: translateX(100%); }
  }

  /* Modal Overlay */
  .last-ticket-overlay {
    position: fixed;
    top: 0; left: 0; width: 100%; height: 100%;
    background: rgba(15, 23, 42, 0.8);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    backdrop-filter: blur(8px);
    padding: 20px;
  }

  .ticket-modal {
    background: white;
    width: 100%;
    max-width: 440px;
    border-radius: var(--radius-2xl);
    overflow: hidden;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
  }

  .modal-header {
    padding: 20px 24px;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .badge-success {
    background: #dcfce7;
    color: #166534;
    padding: 4px 12px;
    border-radius: 99px;
    font-size: 0.75rem;
    font-weight: 700;
    letter-spacing: 1px;
  }

  .close-btn {
    background: none;
    border: none;
    font-size: 1.25rem;
    color: var(--text-muted);
    cursor: pointer;
  }

  .ticket-body {
    padding: 0 40px 40px;
    text-align: center;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .ticket-label {
    font-size: 0.9rem;
    font-weight: 600;
    color: var(--text-muted);
    letter-spacing: 2px;
    margin-bottom: 8px;
  }

  .ticket-number {
    font-size: 7rem;
    font-weight: 950;
    color: var(--primary-dark);
    margin: 0;
    line-height: 1;
    letter-spacing: -4px;
  }

  .ticket-footer {
    margin-top: 24px;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .svc-name {
    font-size: 1.75rem;
    font-weight: 800;
    color: var(--text);
  }

  .timestamp {
    color: var(--text-muted);
    font-size: 0.9rem;
  }

  .modal-actions {
    padding: 24px;
    background: #f8fafc;
    border-top: 1px solid var(--border);
  }

  .btn-block { width: 100%; height: 56px; font-size: 1.1rem; font-weight: 700; }

  .loading-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 100px;
    color: var(--text-muted);
  }

  .spinner {
    width: 48px;
    height: 48px;
    border: 4px solid var(--border);
    border-top-color: var(--primary);
    border-radius: 50%;
    animation: rotate 0.8s linear infinite;
    margin-bottom: 20px;
  }

  @keyframes rotate { to { transform: rotate(360deg); } }

  @media (max-width: 640px) {
    .ticket-number { font-size: 5rem; }
    .services-grid { grid-template-columns: 1fr; }
  }
</style>
