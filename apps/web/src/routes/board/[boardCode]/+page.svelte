<script>
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/stores';
  import { AudioAnnouncementQueue } from '$lib/audio/AudioAnnouncementQueue.js';
  import { DingPlayer } from '$lib/audio/DingPlayer.js';
  import { locale } from '$lib/i18n';
  import QueueBoardView from './_components/QueueBoardView.svelte';

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
  <QueueBoardView {boardCode} {boardData} {clockTime} {loading} {error} {nowCalling} {recentCalls} />
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

  .fade-in {
    animation: fadeIn 0.5s ease-out forwards;
  }
  @keyframes fadeIn {
    from { opacity: 0; transform: translateY(10px); }
    to { opacity: 1; transform: translateY(0); }
  }
</style>
