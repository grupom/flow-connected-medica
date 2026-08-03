<script>
  import { t } from '$lib/i18n';
  import { getModuleColor } from '$lib/board/moduleColors.js';

  export let boardCode;
  export let boardData = null;
  export let clockTime = '';
  export let loading = true;
  export let error = null;
  export let nowCalling = [];
  export let recentCalls = [];
</script>

<div class="board-fullscreen">

  <!-- 1. HEADER -->
  <header class="board-topbar">
    <div class="brand">
      <img src="/logo-medica-white.svg" alt="Médica" class="brand-logo" />
      <span class="brand-fc">Flow Connected</span>
    </div>
    <div class="board-title">{boardData?.board_name ?? boardCode}</div>
    <div class="topbar-controls">
      <div class="clock">{clockTime}</div>
    </div>
  </header>

  {#if loading}
    <div class="board-loading">
      <div class="spin"></div>
      <p>{$t('board.connecting')}</p>
    </div>
  {:else if error}
    <div class="board-error">
      <span class="err-icon">⚠️</span>
      <p>{error}</p>
    </div>
  {:else}
    <main class="board-layout">

      <!-- 2. CENTER AREA - Main Calls -->
      <section class="main-calls-area">
        {#if nowCalling.length === 0}
          <div class="empty-state">
            <span class="empty-icon">☕</span>
            <h2>{$t('board.no_calls')}</h2>
            <p>{$t('board.please_wait')}</p>
          </div>
        {:else}
          <div class="cards-grid" class:single-card={nowCalling.length === 1}>
            {#each nowCalling as ticket, idx (ticket.ticket_id)}
              <div
                class="call-card {idx === 0 ? 'card-primary' : 'card-secondary'} {ticket.isNew && idx === 0 ? 'animate-pulse' : 'fade-in'}"
                style="--accent: {getModuleColor(ticket.prefix)}"
              >
                <div class="card-ticket-number">{ticket.ticket_code}</div>
                <div class="card-arrow">➝</div>
                <div class="card-module-info">
                  <span class="module-label">{$t('board.head_to')}</span>
                  <span class="module-name">{ticket.station_name}</span>
                </div>
              </div>
            {/each}
          </div>
        {/if}
      </section>

      <!-- 3. RIGHT PANEL - Recent Calls & Waiting Counts -->
      <aside class="sidebar-panel">

        <!-- Recent Calls List -->
        <div class="panel-section called-section">
          <div class="panel-header">{$t('board.recent_calls')}</div>
          {#if recentCalls.length === 0}
            <div class="panel-empty">{$t('board.none_recent')}</div>
          {:else}
            <ul class="recent-list">
              {#each recentCalls as ticket (ticket.ticket_id)}
                <li class="recent-item fade-in" style="--accent: {getModuleColor(ticket.prefix)}">
                  <span class="recent-code">{ticket.ticket_code}</span>
                  <span class="recent-arrow">→</span>
                  <span class="recent-module">{ticket.station_name}</span>
                </li>
              {/each}
            </ul>
          {/if}
        </div>

      </aside>
    </main>
  {/if}
</div>

<style>
  .board-fullscreen {
    width: 100vw;
    height: 100vh;
    display: flex;
    flex-direction: column;
    background: #0f172a;
    color: #f8fafc;
  }

  /* 1. Header Styles */
  .board-topbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1.5rem 3rem;
    background: #1e293b;
    border-bottom: 2px solid #0083C3;
    box-shadow: 0 4px 20px rgba(0,0,0,0.3);
    z-index: 10;
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 1rem;
    font-size: 2rem;
  }

  .brand {
    flex-direction: column;
    align-items: flex-start;
    gap: 3px;
  }
  .brand-logo {
    height: 38px;
    width: auto;
    display: block;
  }
  .brand-fc {
    font-size: 0.7rem;
    font-weight: 600;
    letter-spacing: 0.1em;
    text-transform: uppercase;
    color: #94a3b8;
    opacity: 0.8;
  }

  .board-title {
    font-size: 1.8rem;
    font-weight: 600;
    color: #94a3b8;
    text-transform: uppercase;
    letter-spacing: 0.1em;
  }

  .clock {
    font-size: 2.2rem;
    font-weight: 700;
    color: #0083C3;
    font-variant-numeric: tabular-nums;
  }

  /* Topbar Controls */
  .topbar-controls {
    display: flex;
    align-items: center;
    gap: 2rem;
  }

  /* Main Layout Grid */
  .board-layout {
    flex: 1;
    display: flex;
    overflow: hidden;
  }

  /* 2. Center Area (Main Calls) */
  .main-calls-area {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 4rem;
    background: radial-gradient(circle at center, #1e293b 0%, #0f172a 100%);
  }

  .cards-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 3rem;
    width: 100%;
    max-width: 1600px;
    align-items: center;
  }

  /* If only 1 card, make it massive in the center */
  .cards-grid.single-card {
    grid-template-columns: 1fr;
    max-width: 1000px;
  }
  .cards-grid.single-card .card-ticket-number {
    font-size: 14rem;
  }
  .cards-grid.single-card .card-module-info .module-name {
    font-size: 4rem;
  }

  .call-card {
    background: #1e293b;
    border-radius: 32px;
    padding: 3rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    box-shadow: 0 20px 40px rgba(0,0,0,0.4),
                inset 0 0 0 4px var(--accent);
    position: relative;
    overflow: hidden;
    transition: all 0.5s ease;
  }

  /* Primary target gets full highlight */
  .card-primary {
    opacity: 1;
    transform: scale(1.02);
    box-shadow: 0 30px 60px rgba(0,0,0,0.6),
                inset 0 0 0 6px var(--accent);
  }

  /* Secondary targets are slightly dimmed to emphasize the newest ticket */
  .card-secondary {
    opacity: 0.8;
    transform: scale(0.96);
    filter: brightness(0.85);
  }

  /* Subtle glow based on module color */
  .call-card::before {
    content: '';
    position: absolute;
    top: 0; left: 0; right: 0; height: 100%;
    background: linear-gradient(180deg, var(--accent) 0%, transparent 40%);
    opacity: 0.1;
    pointer-events: none;
  }

  .card-ticket-number {
    font-size: 10rem;
    font-weight: 900;
    line-height: 1;
    color: #ffffff;
    letter-spacing: -0.03em;
    text-shadow: 0 10px 30px rgba(0,0,0,0.5);
    margin-bottom: 0.5rem;
  }

  .card-arrow {
    font-size: 4rem;
    color: var(--accent);
    margin: 1rem 0;
    line-height: 0.5;
  }

  .card-module-info {
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  .module-label {
    font-size: 1.5rem;
    font-weight: 600;
    color: #94a3b8;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    margin-bottom: 0.5rem;
  }

  .module-name {
    font-size: 3rem;
    font-weight: 800;
    color: var(--accent);
    line-height: 1.2;
  }

  .empty-state {
    text-align: center;
    color: #475569;
  }
  .empty-icon { font-size: 8rem; display: block; margin-bottom: 1rem; opacity: 0.5; }
  .empty-state h2 { font-size: 3rem; color: #64748b; margin-bottom: 1rem; }
  .empty-state p { font-size: 1.8rem; }

  /* 3. Right Panel */
  .sidebar-panel {
    width: 25%;
    min-width: 450px;
    background: #1e293b;
    border-left: 2px solid #334155;
    display: flex;
    flex-direction: column;
    box-shadow: -10px 0 30px rgba(0,0,0,0.2);
    z-index: 5;
  }

  .panel-section {
    padding: 2.5rem;
    display: flex;
    flex-direction: column;
  }
  .called-section {
    flex: 1;
    border-bottom: none;
    display: flex;
    flex-direction: column;
  }

  .panel-header {
    font-size: 1.6rem;
    font-weight: 700;
    color: #94a3b8;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    margin-bottom: 2rem;
    border-left: 6px solid #0083C3;
    padding-left: 1rem;
  }

  /* Recent List */
  .recent-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 1.2rem;
    flex: 1;
    overflow-y: hidden;
  }

  .recent-item {
    background: #0f172a;
    border-radius: 12px;
    padding: 1.25rem 1.5rem;
    display: flex;
    align-items: center;
    justify-content: space-between;
    border-left: 6px solid var(--accent);
  }

  .recent-code {
    font-size: 2.5rem;
    font-weight: 800;
    color: #f1f5f9;
  }

  .recent-arrow {
    font-size: 1.5rem;
    color: #64748b;
  }

  .recent-module {
    font-size: 1.8rem;
    font-weight: 600;
    color: var(--accent);
    text-align: right;
  }

  /* Status States */
  .board-loading, .board-error {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    font-size: 2rem;
    color: #94a3b8;
  }
  .board-error { color: #ef4444; }
  .spin {
    width: 60px; height: 60px;
    border: 6px solid #334155;
    border-top-color: #0083C3;
    border-radius: 50%;
    animation: spin 1s linear infinite;
    margin-bottom: 1.5rem;
  }

  /* Animations */
  @keyframes spin { 100% { transform: rotate(360deg); } }

  .fade-in {
    animation: fadeIn 0.5s ease-out forwards;
  }
  @keyframes fadeIn {
    from { opacity: 0; transform: translateY(10px); }
    to { opacity: 1; transform: translateY(0); }
  }

  .animate-pulse {
    animation: callPulse 2s ease-out;
  }
  @keyframes callPulse {
    0% { transform: scale(0.95); box-shadow: 0 0 0 0px var(--accent); }
    10% { transform: scale(1.05); box-shadow: 0 0 0 40px rgba(59,130,246, 0); }
    100% { transform: scale(1); box-shadow: 0 0 0 0px rgba(59,130,246, 0); }
  }
</style>
