<script>
  import { base } from '$app/paths';
</script>

<svelte:head>
  <title>Reports & Analytics — Admin</title>
</svelte:head>

<div class="page-header">
  <div>
    <h2 class="page-title">Reports & Analytics</h2>
    <p class="page-subtitle">Select a report or dashboard to analyze queue operations and demand.</p>
  </div>
</div>

<div class="reports-grid">

  <!-- 1. Ticket History -->
  <a href="/admin/reports/ticket-history" class="report-card">
    <div class="icon-wrap bg-primary">
      <span class="icon">🧾</span>
    </div>
    <div class="report-meta">
      <h3>Ticket History</h3>
      <p>Historial completo de turnos emitidos y gestionados en el sistema.</p>
    </div>
    <div class="arrow">→</div>
  </a>

  <!-- 2. Waiting Time -->
  <a href="/admin/reports/waiting-time" class="report-card">
    <div class="icon-wrap bg-warning">
      <span class="icon">⏳</span>
    </div>
    <div class="report-meta">
      <h3>Waiting Time</h3>
      <p>Métricas de tiempo de espera por módulo y por estación a lo largo del día.</p>
    </div>
    <div class="arrow">→</div>
  </a>

  <!-- 3. Congestion & Demand -->
  <a href="/admin/reports/congestion-demand" class="report-card">
    <div class="icon-wrap bg-danger">
      <span class="icon">📈</span>
    </div>
    <div class="report-meta">
      <h3>Congestion & Demand</h3>
      <p>Dashboard de carga operativa, picos de demanda y volúmenes simultáneos.</p>
    </div>
    <div class="arrow">→</div>
  </a>

  <!-- 4. Tickets by Station / Area -->
  <a href="/admin/reports/tickets-by-station-area" class="report-card">
    <div class="icon-wrap bg-success">
      <span class="icon">🏢</span>
    </div>
    <div class="report-meta">
      <h3>Tickets by Station / Area</h3>
      <p>Volumen de tickets según estación o módulo, con desglose por estado.</p>
    </div>
    <div class="arrow">→</div>
  </a>

</div>

<style>
  .reports-grid {
    display: grid;
    /* 4 Columns in Wide Desktop, gracefully adapting on smaller screens */
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: 24px;
    margin-top: 24px;
  }

  .report-card {
    display: flex;
    flex-direction: column;
    padding: 24px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    text-decoration: none;
    color: inherit;
    transition: all 0.2s ease;
    box-shadow: 0 1px 3px rgba(0,0,0,0.05);
    height: 100%;
    position: relative;
    overflow: hidden;
  }

  .report-card:hover {
    transform: translateY(-4px);
    box-shadow: 0 12px 24px rgba(0,0,0,0.1);
    border-color: var(--primary);
  }

  .icon-wrap {
    width: 56px;
    height: 56px;
    border-radius: 16px;
    display: flex;
    align-items: center;
    justify-content: center;
    margin-bottom: 20px;
    font-size: 24px;
  }

  /* Soft Background Utilities for Icons */
  .bg-primary { background: rgba(59, 130, 246, 0.1); }
  .bg-warning { background: rgba(245, 158, 11, 0.1); }
  .bg-danger { background: rgba(239, 68, 68, 0.1); }
  .bg-success { background: rgba(16, 185, 129, 0.1); }

  .report-meta {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .report-meta h3 {
    margin: 0;
    font-size: 1.1rem;
    font-weight: 600;
    color: var(--text);
  }

  .report-meta p {
    margin: 0;
    font-size: 0.9rem;
    color: var(--muted);
    line-height: 1.5;
  }

  .arrow {
    position: absolute;
    bottom: 24px;
    right: 24px;
    font-size: 1.2rem;
    color: #94a3b8;
    opacity: 0;
    transform: translateX(-10px);
    transition: all 0.2s ease;
  }

  .report-card:hover .arrow {
    opacity: 1;
    transform: translateX(0);
    color: var(--primary);
  }
</style>
