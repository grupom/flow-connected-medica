<script>
  import { onMount } from 'svelte';
  import { api } from '$lib/api.js';
  import { auth } from '$lib/auth.js';
  import { goto } from '$app/navigation';
  import { printTicket } from '$lib/printing/printTicket.js';
  import { t, locale } from '$lib/i18n';
  import LanguageSwitcher from '$lib/components/LanguageSwitcher.svelte';

  // ── State ────────────────────────────────────────────────────
  let services     = []; // { prefix, service_name, icon, ... }
  let currentKiosk = null;
  let loading      = true;
  let issuing      = false;
  let ticket       = null; // { code, prefix } after issue
  let countdown    = 0;
  let timer        = null;
  let error        = '';
  let multiLanguage = false;

  // ── Auth guard / Load ───────────────────────────────────────────────
  onMount(async () => {
    // Load system settings (public endpoint)
    try {
      const settingsRes = await api.public.get('/api/settings');
      multiLanguage = settingsRes.data.multi_language ?? false;
      if (!multiLanguage) locale.set('es');
    } catch { /* Non-critical */ }
    // 1. Check valid JWT Session
    const authState = await new Promise(r => {
      let unsub;
      unsub = auth.subscribe(v => { 
        if (v !== undefined) { 
          if (unsub) unsub(); 
          else setTimeout(() => unsub && unsub(), 0);
          r(v); 
        } 
      });
    });
    
    if (!authState?.user) { 
        goto('/kiosk/login'); 
        return; 
    }
    
    await loadServices();
  });

  async function loadServices() {
    loading = true;
    error   = '';
    try {
      // 2. Load strictly authorized queues from Kiosk endpoint
      const res = await api.get('/api/kiosk/session');
      currentKiosk = res.data.kiosk;
      
      // Map properties for UI rendering
      services = res.data.allowedQueues.map(q => ({
        prefix: q.prefix,
        label: q.service_name,
        icon: q.icon || '🏷️', 
        color: `var(--${q.prefix === 'E' ? 'danger' : q.prefix === 'C' ? 'primary' : q.prefix === 'L' ? 'warning' : q.prefix === 'P' ? 'purple' : 'success'})`
      }));
      
    } catch (e) {
      if (e.statusCode === 403 || e.statusCode === 401) {
          auth.logout();
          goto('/kiosk/login');
      } else {
          error = e.message || $t('kiosk.error_load_config');
      }
    } finally {
      loading = false;
    }
  }

  // ── Issue ticket ─────────────────────────────────────────────
  async function issueTicket(prefix) {
    if (issuing) return;
    issuing = true;
    error   = '';
    try {
      // 3. Dispatch to secure /api/kiosk endpoint
      const res = await api.post('/api/kiosk/issue-ticket', { prefix });
      ticket = res?.data ?? res;

      // Trigger thermal printing via agent
      try {
          const svc = services.find(s => s.prefix === prefix);
          await printTicket({
              code: ticket.code,
              prefix: ticket.prefix,
              service_name: ticket.service_name || svc?.label,
              tck_number: ticket.tck_number
          });
      } catch (printErr) {
          error = printErr.message || $t('kiosk.error_print');
      }

      startCountdown(5);
    } catch (e) {
      error = e.message || $t('kiosk.error_issue');
    } finally {
      issuing = false;
    }
  }

  function startCountdown(secs) {
    countdown = secs;
    clearInterval(timer);
    timer = setInterval(() => {
      countdown--;
      if (countdown <= 0) reset();
    }, 1000);
  }

  function reset() {
    clearInterval(timer);
    ticket    = null;
    countdown = 0;
    error     = '';
  }
</script>

<svelte:head>
  <title>{$t('kiosk.title')}</title>
</svelte:head>

<main class="kiosk-root">
  <!-- Header -->
  <header class="kiosk-header fade-in">
    <div class="k-brand">
      <img src="/logo-medica.svg" alt="Médica" class="k-logo-img" />
      <p class="k-sub">{$t('kiosk.subtitle')}</p>
    </div>
    {#if multiLanguage}
    <div style="margin-left: auto; display: flex; align-items: center; padding-right: 20px;">
      <LanguageSwitcher />
    </div>
    {/if}
  </header>

  <!-- Error banner -->
  {#if error}
    <div class="k-error fade-in">{error}</div>
  {/if}

  <div class="k-content-wrapper fade-in">
    <!-- Loading -->
    {#if loading}
      <div class="k-center">
        <div class="k-spinner"></div>
        <p class="k-hint-text">{$t('kiosk.loading_areas')}</p>
      </div>

    <!-- Ticket issued ✅ -->
    {:else if ticket}
      <div class="k-result-panel">
        <div class="k-check-icon">✅</div>
        <h2 class="k-result-title">{$t('kiosk.your_turn')}</h2>
        
        <div class="k-ticket-code">{ticket.code ?? ticket.prefix + ticket.tck_number}</div>
        
        <p class="k-wait-text">{$t('kiosk.wait_to_be_called')}</p>

        <div class="k-progress-container">
          <div class="k-progress-bar" style="animation-duration:{countdown + 1}s"></div>
        </div>
        <p class="k-timeout-text">{$t('kiosk.returning_in', { time: countdown })}</p>
        
        <button class="btn btn-ghost k-reset-btn" on:click={reset}>{$t('kiosk.return_now')}</button>
      </div>

    <!-- Service selection -->
    {:else}
      <div class="k-selection-panel">
        <h2 class="k-prompt">{$t('kiosk.select_area')}</h2>
        <p class="k-prompt-sub">{$t('kiosk.touch_option')}</p>
        
        <div class="k-grid" class:k-grid-single={services.length === 1}>
          {#each services as svc}
            <button
              class="k-card card"
              style="--accent:{svc.color}"
              on:click={() => issueTicket(svc.prefix)}
              disabled={issuing}
            >
              <div class="k-card-icon">{svc.icon}</div>
              <div class="k-card-content">
                <span class="k-card-label">{svc.label}</span>
                <span class="k-card-prefix">{$t('kiosk.area_prefix', { prefix: svc.prefix })}</span>
              </div>
            </button>
          {/each}
        </div>
      </div>
    {/if}
  </div>

  <!-- Footer -->
  <footer class="kiosk-footer fade-in">
    <button class="k-admin-link btn btn-ghost" on:click={() => { auth.logout(); goto('/kiosk/login'); }} style="border:none">
      {$t('kiosk.close_terminal')}
    </button>
    <span class="k-footer-sep">·</span>
    <span>{currentKiosk?.kiosk_name || $t('kiosk.building_terminal')}</span>
    <span class="k-footer-sep">·</span>
    <span>{new Date().toLocaleTimeString('es-DO', { hour: '2-digit', minute: '2-digit' })}</span>
  </footer>
</main>

<style>
  /* ── Reset & Root ─────────────────────────────────── */
  :global(body) { margin: 0; }

  .kiosk-root {
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
    align-items: center;
    background: var(--bg);
    color: var(--text);
    padding: 0 32px 32px;
    box-sizing: border-box;
    font-family: 'Inter', system-ui, sans-serif;
  }

  /* ── Header ───────────────────────────────────────── */
  .kiosk-header {
    width: 100%;
    max-width: 1200px;
    padding: 40px 0 20px;
    display: flex;
    justify-content: center;
    border-bottom: 2px solid var(--border);
    margin-bottom: 40px;
  }

  .k-brand {
    display: flex;
    align-items: center;
    gap: 20px;
  }
  .k-logo-img { height: 72px; width: auto; display: block; }
  .k-title { margin: 0; font-size: 2.5rem; font-weight: 800; color: var(--text); letter-spacing: -1px; }
  .k-sub { margin: 4px 0 0; font-size: 1.1rem; color: var(--text-muted); font-weight: 500; }

  /* ── Error container ──────────────────────────────── */
  .k-error {
    background: var(--danger-light);
    color: var(--danger);
    border: 1px solid rgba(239,68,68,0.3);
    padding: 16px 24px;
    border-radius: var(--radius-md);
    margin-bottom: 24px;
    font-weight: 500;
    max-width: 600px;
    text-align: center;
  }

  /* ── Layout Wrapper ───────────────────────────────── */
  .k-content-wrapper {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    width: 100%;
    max-width: 1200px;
  }

  /* ── Loading ──────────────────────────────────────── */
  .k-center {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 24px;
  }
  .k-spinner {
    width: 64px; height: 64px;
    border: 6px solid var(--border);
    border-top-color: var(--primary);
    border-radius: 50%;
    animation: k-spin 1s linear infinite;
  }
  @keyframes k-spin { to { transform: rotate(360deg); } }
  
  .k-hint-text {
    font-size: 1.2rem;
    color: var(--text-muted);
    font-weight: 500;
  }

  /* ── Selection Panel (Home) ───────────────────────── */
  .k-selection-panel {
    display: flex;
    flex-direction: column;
    align-items: center;
    width: 100%;
    animation: k-fade-up 0.4s ease-out;
  }
  @keyframes k-fade-up {
    from { opacity: 0; transform: translateY(20px); }
    to { opacity: 1; transform: translateY(0); }
  }

  .k-prompt {
    font-size: 2.25rem;
    font-weight: 800;
    color: var(--text);
    margin: 0 0 8px 0;
    text-align: center;
  }
  .k-prompt-sub {
    font-size: 1.2rem;
    color: var(--text-muted);
    margin: 0 0 48px 0;
    text-align: center;
  }

  /* ── Grid & Cards ─────────────────────────────────── */
  .k-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
    gap: 32px;
    width: 100%;
    max-width: 1000px;
  }

  /* Una sola opción: mismo ancho que una card en grilla de 2 columnas, centrada */
  .k-grid.k-grid-single {
    grid-template-columns: minmax(320px, 484px);
    justify-content: center;
  }

  .k-card {
    display: flex;
    flex-direction: row;
    align-items: center;
    gap: 24px;
    padding: 32px 40px;
    border-radius: var(--radius-xl);
    cursor: pointer;
    transition: transform 0.2s cubic-bezier(0.34, 1.56, 0.64, 1), box-shadow 0.2s, border-color 0.2s;
    background: var(--surface);
    border: 2px solid var(--border);
    text-align: left;
    position: relative;
    overflow: hidden;
  }
  .k-card::after {
    content: '';
    position: absolute;
    left: 0; top: 0; bottom: 0;
    width: 8px;
    background: var(--accent);
    opacity: 0.8;
  }

  .k-card:hover:not(:disabled) {
    transform: translateY(-6px) scale(1.02);
    box-shadow: var(--shadow-xl);
    border-color: var(--accent);
  }
  .k-card:active:not(:disabled) {
    transform: scale(0.98);
  }
  .k-card:disabled {
    opacity: 0.6;
    cursor: wait;
    filter: grayscale(1);
  }

  .k-card-icon {
    font-size: 4rem;
    line-height: 1;
  }
  
  .k-card-content {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .k-card-label {
    font-size: 1.75rem;
    font-weight: 800;
    color: var(--text);
    letter-spacing: -0.5px;
  }
  
  .k-card-prefix {
    font-size: 1.1rem;
    color: var(--text-muted);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  /* ── Ticket Issued Panel ──────────────────────────── */
  .k-result-panel {
    background: var(--surface);
    border: 1px solid var(--border);
    box-shadow: var(--shadow-xl);
    border-radius: var(--radius-xl);
    padding: 48px 40px;
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    width: 100%;
    margin: 0 auto;
    max-width: 450px;
    animation: k-pop 0.5s cubic-bezier(0.34, 1.56, 0.64, 1);
  }
  @keyframes k-pop {
    from { opacity: 0; transform: scale(0.9); }
    to { opacity: 1; transform: scale(1); }
  }

  .k-check-icon {
    font-size: 4rem;
    margin-bottom: 20px;
    line-height: 1;
  }

  .k-result-title {
    font-size: 1.6rem;
    font-weight: 700;
    color: var(--text-muted);
    margin: 0 0 12px 0;
  }

  .k-ticket-code {
    font-size: clamp(4.5rem, 12vw, 7rem);
    font-weight: 900;
    color: var(--primary-dark);
    letter-spacing: -3px;
    line-height: 1;
    margin-bottom: 20px;
  }

  .k-wait-text {
    font-size: 1.25rem;
    font-weight: 600;
    color: var(--text);
    margin: 0 0 8px 0;
  }
  
  .k-progress-container {
    width: 100%;
    max-width: 400px;
    height: 8px;
    background: var(--border);
    border-radius: var(--radius-pill);
    overflow: hidden;
    margin-bottom: 16px;
  }

  .k-progress-bar {
    height: 100%;
    width: 100%;
    background: var(--primary);
    border-radius: var(--radius-pill);
    transform-origin: left;
    animation: k-shrink linear forwards;
  }
  @keyframes k-shrink {
    from { transform: scaleX(1); }
    to { transform: scaleX(0); }
  }

  .k-timeout-text {
    font-size: 1.1rem;
    color: var(--text-muted);
    margin: 0 0 24px 0;
  }

  .k-reset-btn {
    font-size: 1.2rem;
    padding: 16px 32px;
    border-radius: var(--radius-pill);
  }

  /* ── Footer ───────────────────────────────────────── */
  .kiosk-footer {
    width: 100%;
    max-width: 1200px;
    padding-top: 24px;
    border-top: 1px solid var(--border);
    margin-top: 40px;
    display: flex;
    justify-content: center;
    align-items: center;
    gap: 16px;
    font-size: 1.1rem;
    color: var(--text-muted);
    font-weight: 500;
  }

  .k-admin-link {
    color: var(--text-muted);
    text-decoration: none;
    transition: color 0.2s;
  }
  .k-admin-link:hover {
    color: var(--primary);
  }

  .k-footer-sep {
    opacity: 0.5;
  }

  /* ── Media Queries ────────────────────────────────── */
  @media (max-width: 768px) {
    .kiosk-root { padding: 0 16px 24px; }
    .kiosk-header { padding: 24px 0 16px; margin-bottom: 24px; }
    .k-logo-img { height: 52px; }
    .k-title { font-size: 1.8rem; }
    
    .k-prompt { font-size: 1.8rem; }
    .k-prompt-sub { font-size: 1rem; margin-bottom: 32px; }
    
    .k-grid { grid-template-columns: 1fr; gap: 16px; }
    .k-card { padding: 24px; gap: 16px; }
    .k-card-icon { font-size: 3rem; }
    .k-card-label { font-size: 1.5rem; }
    
    .k-result-panel { padding: 32px 24px; }
    .k-ticket-code { font-size: 5rem; }
    .k-wait-text { font-size: 1.25rem; }
  }

</style>
