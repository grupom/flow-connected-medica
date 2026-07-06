<script>
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/stores';
  import { AudioAnnouncementQueue } from '$lib/audio/AudioAnnouncementQueue.js';
  import { DingPlayer } from '$lib/audio/DingPlayer.js';
  import { t, locale } from '$lib/i18n';

  const API_BASE = import.meta.env.PUBLIC_API_URL ?? '';

  let boardCode = $page.params.boardCode;
  let boardData = null;
  
  // Data State
  let nowCalling = [];      // Main prominent ticket calls
  let recentCalls = [];     // Historical list 
  let inService = [];       // (optional) currently active
  let waitingCounts = [];
  
  let loading = true;
  let error = null;
  let interval = null;
  
  let audioEnabled = false;
  let clockTime = '';
  let initialLoadComplete = false;
  let audioQueue = null; // Instantiated on mount to avoid SSR issues

  // ── Ad rotation state machine ──────────────────────────────────────────────
  // AD_PLAYING: full-screen ad (video or image sequence) is showing.
  // QUEUE_ROTATION: showing the queue board as part of the normal ad->queue->ad cycle.
  // QUEUE_INTERRUPTED: a call arrived mid-ad; showing the queue board until the
  // interrupt cooldown elapses, then the ad resumes from where it was paused.
  const PHASE = { AD_PLAYING: 'AD_PLAYING', QUEUE_ROTATION: 'QUEUE_ROTATION', QUEUE_INTERRUPTED: 'QUEUE_INTERRUPTED' };
  let phase = PHASE.QUEUE_ROTATION;
  let adInitialized = false;
  let adSavedPosition = null;      // video: seconds (number) | image sequence: { imageIndex, elapsedMs }
  let pendingResumeSeconds = null; // consumed by the <video> element's loadedmetadata handler
  let cooldownTimer = null;
  let rotationTimer = null;
  let imageSequenceTimer = null;
  let currentImageIndex = 0;
  let currentImageStartedAt = 0;
  let videoEl;
  // Map module prefixes to colors for UI aesthetics.
  // Supports both single-letter (C, L, E…) and multi-letter (PD, RX…) prefixes.
  // Full prefix is checked first; falls back to first letter, then default.
  const moduleColors = {
    'C':  '#0083C3', // Consultorio  -> Médica Blue
    'L':  '#a855f7', // Laboratorio  -> Purple
    'E':  '#ef4444', // Emergencia   -> Red
    'O':  '#10b981', // Odontología  -> Green
    'P':  '#f59e0b', // Psicología   -> Amber
    'PD': '#0083C3', // Pediatría    -> Médica Blue
    'default': '#0083C3' // Médica Blue
  };

  function getModuleColor(prefix) {
    if (!prefix) return moduleColors.default;
    const upper = prefix.toUpperCase();
    // 1. Exact match (handles multi-letter prefixes like PD)
    if (moduleColors[upper]) return moduleColors[upper];
    // 2. Fallback to first letter
    const firstLetter = upper.charAt(0);
    return moduleColors[firstLetter] || moduleColors.default;
  }

  function updateClock() {
    clockTime = new Date().toLocaleTimeString('es-DO', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  // Check if a list of tickets contains any new IDs or an updated called_at timestamp (for Recalls)
  function getNewTickets(prevList, newList) {
    const prevMap = new Map((prevList || []).map(t => [t.ticket_id, t]));
    return (newList || []).filter(t => {
      const p = prevMap.get(t.ticket_id);
      if (!p) return true; // brand new
      // It's a recall if it has a newer timestamp
      if (t.called_at && p.called_at && new Date(t.called_at).getTime() > new Date(p.called_at).getTime()) return true;
      return false;
    });
  }

  async function fetchSnapshot() {
    try {
      const res = await fetch(`${API_BASE}/api/boards/${boardCode}/snapshot`);
      if (!res.ok) throw new Error(`Board not found (${res.status})`);
      const data = await res.json();
      boardData = data.board ?? data;
      
      if (boardData?.language) {
          locale.set(boardData.language);
      }
      
      if (audioQueue) {
          audioQueue.speechRateMultiplier = parseFloat(boardData?.voice_speed ?? 1.0);
          audioQueue.dingVariant = boardData?.ding_sound || 'gentle';
      }
      
      const incomingCalling = data.now_calling ?? [];
      inService = data.in_service ?? [];
      waitingCounts = data.waiting_counts ?? [];

      // Detect new tickets in now_calling to play sound & animate
      if (initialLoadComplete) {
        const newTickets = getNewTickets(nowCalling, incomingCalling);
        if (newTickets.length > 0) {
          // Add animation flagging to new tickets
          incomingCalling.forEach(t => {
            if (newTickets.find(n => n.ticket_id === t.ticket_id)) {
              t.isNew = true;
              // Add to the sequential audio queue manager!
              if (audioQueue && audioEnabled) {
                audioQueue.enqueue(t);
              }
            }
          });
          onNewCallDetected();
        }
      } else {
        initialLoadComplete = true; // Mark first load done
        if (!adInitialized) {
          adInitialized = true;
          initAdPlayback();
        }
      }

      // Build recent calls history: last 10 called tickets
      let allActive = [...incomingCalling, ...inService]
        .sort((a, b) => new Date(b.called_at || b.started_at || 0) - new Date(a.called_at || a.started_at || 0));
      
      // Sort nowCalling by called_at DESC to make the freshest ticket always on top/first
      nowCalling = incomingCalling.sort((a, b) => new Date(b.called_at || 0) - new Date(a.called_at || 0));
      recentCalls = allActive.slice(0, 10); 
      
      error = null;
    } catch (e) {
      error = e.message;
    } finally {
      loading = false;
    }
  }

  function enableAudio() {
    audioEnabled = true;
    // Attempt to unlock AudioContext (works on TV browsers and kiosk Chromium;
    // on Chrome desktop it will succeed after the first user interaction below)
    DingPlayer.unlock();
    if (window.speechSynthesis) {
      const u = new SpeechSynthesisUtterance('');
      u.volume = 0;
      window.speechSynthesis.speak(u);
    }
  }

  // ── Ad rotation: persistence (survives a page reload / TV reboot) ──────────
  function storageKey() {
    return `board_ad_state_${boardCode}`;
  }

  function persistAdState() {
    if (!boardData) return;
    try {
      localStorage.setItem(storageKey(), JSON.stringify({
        version: boardData.ad_version,
        phase,
        position: adSavedPosition,
      }));
    } catch { /* localStorage unavailable — not critical, just skip persistence */ }
  }

  // Returns true if playback was restored into AD_PLAYING; false means the
  // caller should fall back to the normal "start ad from beginning" init.
  function restoreAdState() {
    try {
      const raw = localStorage.getItem(storageKey());
      if (!raw) return false;
      const saved = JSON.parse(raw);
      if (!saved || saved.version !== boardData.ad_version) return false; // stale — media changed since
      if (saved.phase !== PHASE.AD_PLAYING && saved.phase !== PHASE.QUEUE_INTERRUPTED) return false;
      if (!boardData.ad_media_type || boardData.ad_media_type === 'none') return false;

      phase = PHASE.AD_PLAYING;
      if (boardData.ad_media_type === 'video') {
        pendingResumeSeconds = saved.position ?? 0;
      } else {
        currentImageIndex = saved.position?.imageIndex ?? 0;
        scheduleCurrentImage(saved.position?.elapsedMs ?? 0);
      }
      return true;
    } catch {
      return false;
    }
  }

  // ── Ad rotation: init + priority interrupt ─────────────────────────────────
  function initAdPlayback() {
    const restored = restoreAdState();
    if (!restored && boardData?.ad_media_type && boardData.ad_media_type !== 'none') {
      startAdFromBeginning();
    }
  }

  // Called whenever the poll loop detects a brand-new call. If an ad is
  // currently playing, pause it (remembering the exact position) and switch
  // to the queue view. Whether this is the first interrupt or another call
  // arrives while already interrupted, (re)start the cooldown countdown —
  // the ad only resumes once calls stop arriving for the configured window.
  function onNewCallDetected() {
    if (!boardData?.ad_media_type || boardData.ad_media_type === 'none') return;
    if (phase === PHASE.AD_PLAYING) {
      savePlaybackPosition();
      pauseAd();
      phase = PHASE.QUEUE_INTERRUPTED;
      persistAdState();
    }
    clearTimeout(cooldownTimer);
    cooldownTimer = setTimeout(resumeAdFromSavedPosition, (boardData?.ad_interrupt_cooldown_seconds ?? 8) * 1000);
  }

  function savePlaybackPosition() {
    if (boardData.ad_media_type === 'video' && videoEl) {
      adSavedPosition = videoEl.currentTime;
    } else if (boardData.ad_media_type === 'image_sequence') {
      adSavedPosition = { imageIndex: currentImageIndex, elapsedMs: Date.now() - currentImageStartedAt };
    }
    clearTimeout(imageSequenceTimer);
  }

  function pauseAd() {
    if (boardData.ad_media_type === 'video' && videoEl) videoEl.pause();
  }

  function resumeAdFromSavedPosition() {
    if (!boardData?.ad_media_type || boardData.ad_media_type === 'none') return;
    phase = PHASE.AD_PLAYING;
    if (boardData.ad_media_type === 'video') {
      pendingResumeSeconds = adSavedPosition ?? 0;
    } else if (boardData.ad_media_type === 'image_sequence') {
      currentImageIndex = adSavedPosition?.imageIndex ?? 0;
      scheduleCurrentImage(adSavedPosition?.elapsedMs ?? 0);
    }
    adSavedPosition = null;
    persistAdState();
  }

  function startAdFromBeginning() {
    phase = PHASE.AD_PLAYING;
    if (boardData.ad_media_type === 'video') {
      pendingResumeSeconds = 0;
    } else if (boardData.ad_media_type === 'image_sequence') {
      currentImageIndex = 0;
      scheduleCurrentImage(0);
    }
    persistAdState();
  }

  function handleVideoLoadedMetadata() {
    if (pendingResumeSeconds != null && videoEl) {
      videoEl.currentTime = pendingResumeSeconds;
      pendingResumeSeconds = null;
    }
  }

  // Video played fully through (normal rotation, not an interrupt) — show the
  // queue board for ad_rotation_seconds before looping back to the ad.
  function handleVideoEnded() {
    phase = PHASE.QUEUE_ROTATION;
    persistAdState();
    startQueueRotationTimer();
  }

  function preloadNextImage() {
    const images = boardData?.ad_images ?? [];
    if (!images.length) return;
    const nextImg = images[(currentImageIndex + 1) % images.length];
    if (nextImg?.url) new Image().src = nextImg.url;
  }

  function scheduleCurrentImage(alreadyElapsedMs = 0) {
    const img = boardData?.ad_images?.[currentImageIndex];
    if (!img) {
      phase = PHASE.QUEUE_ROTATION;
      persistAdState();
      startQueueRotationTimer();
      return;
    }
    const remainingMs = Math.max((img.duration_seconds * 1000) - alreadyElapsedMs, 0);
    currentImageStartedAt = Date.now() - alreadyElapsedMs;
    clearTimeout(imageSequenceTimer);
    imageSequenceTimer = setTimeout(advanceImage, remainingMs);
    preloadNextImage();
  }

  // Full sequence played through once — equivalent to the video's `ended` event.
  function advanceImage() {
    const images = boardData?.ad_images ?? [];
    if (currentImageIndex + 1 < images.length) {
      currentImageIndex++;
      scheduleCurrentImage(0);
    } else {
      currentImageIndex = 0;
      phase = PHASE.QUEUE_ROTATION;
      persistAdState();
      startQueueRotationTimer();
    }
  }

  // Normal rotation: after the queue board has been visible for
  // ad_rotation_seconds (and nothing interrupted it), loop back to the ad.
  function startQueueRotationTimer() {
    clearTimeout(rotationTimer);
    rotationTimer = setTimeout(() => {
      if (boardData?.ad_media_type && boardData.ad_media_type !== 'none') {
        startAdFromBeginning();
      }
    }, (boardData?.ad_rotation_seconds ?? 20) * 1000);
  }

  onMount(() => {
    // Instantiate exactly client-side
    audioQueue = new AudioAnnouncementQueue({ apiBase: API_BASE });
    updateClock();
    fetchSnapshot();
    enableAudio();

    // Passive listeners: unlock AudioContext on the first user interaction.
    // Required by Chrome desktop autoplay policy; harmless on TV browsers.
    const unlock = () => DingPlayer.unlock();
    document.addEventListener('click',      unlock, { once: true, passive: true });
    document.addEventListener('touchstart', unlock, { once: true, passive: true });
    document.addEventListener('keydown',    unlock, { once: true, passive: true });

    interval = setInterval(fetchSnapshot, 2000); // 2 seconds auto-refresh
    const clockInterval = setInterval(updateClock, 1000);
    return () => {
      clearInterval(interval);
      clearInterval(clockInterval);
      clearTimeout(cooldownTimer);
      clearTimeout(rotationTimer);
      clearTimeout(imageSequenceTimer);
    };
  });
</script>

<svelte:head>
  <title>{boardData?.board_name ?? 'Queue Board'} | Flow Connected</title>
</svelte:head>

{#if phase === PHASE.AD_PLAYING && boardData?.ad_media_type === 'video' && boardData?.ad_video_url}
  <div class="ad-fullscreen">
    <video
      bind:this={videoEl}
      src={boardData.ad_video_url}
      autoplay
      muted
      playsinline
      on:loadedmetadata={handleVideoLoadedMetadata}
      on:ended={handleVideoEnded}
      class="ad-media"
    >
      <track kind="captions" />
    </video>
  </div>
{:else if phase === PHASE.AD_PLAYING && boardData?.ad_media_type === 'image_sequence' && boardData?.ad_images?.length}
  <div class="ad-fullscreen">
    {#key currentImageIndex}
      <img src={boardData.ad_images[currentImageIndex]?.url} alt="" class="ad-media fade-in" />
    {/key}
  </div>
{:else}
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
{/if}

<style>
  /* Base Reset for TV Screen */
  :global(body) {
    margin: 0;
    padding: 0;
    overflow: hidden; /* Prevent scrolling on TV */
    background-color: #0f172a;
    font-family: 'Inter', system-ui, sans-serif;
  }

  .board-fullscreen {
    width: 100vw;
    height: 100vh;
    display: flex;
    flex-direction: column;
    background: #0f172a;
    color: #f8fafc;
  }

  /* Ad rotation: full-screen video/image takeover */
  .ad-fullscreen {
    width: 100vw;
    height: 100vh;
    background: #000;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
  }
  .ad-media {
    width: 100%;
    height: 100%;
    object-fit: contain;
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
