/**
 * DingPlayer — plays a notification chime using Web Audio API synthesis.
 *
 * Variants (no extra audio files required):
 *   gentle  – very soft, low-frequency bell (default for all boards)
 *   soft    – moderately soft chime
 *   classic – the original ding.mp3 file
 *
 * Chrome autoplay policy: AudioContext must be created/resumed after a user
 * gesture. DingPlayer keeps a singleton context and exposes unlock() which
 * should be called on the first user interaction (click / touchstart).
 * On Smart TV browsers and Chromium kiosk mode the restriction is relaxed
 * and audio works without any gesture.
 */

export const DING_OPTIONS = [
  { value: 'gentle',  label: 'Suave (recomendado)' },
  { value: 'soft',    label: 'Moderado' },
  { value: 'classic', label: 'Clásico' },
];

const VARIANTS = {
  gentle:  { freq: 330, overtone: 660,  gain: 0.13, overtoneGain: 0.25, attack: 0.015, decay: 2.0 },
  soft:    { freq: 440, overtone: 880,  gain: 0.28, overtoneGain: 0.30, attack: 0.008, decay: 1.4 },
  classic: null, // uses /sounds/ding.mp3
};

// ── Singleton AudioContext ────────────────────────────────────────────────────
let _ctx = null;

function getContext() {
  if (!_ctx) {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    _ctx = new AC();
  }
  return _ctx;
}

/** Resume the AudioContext if it was suspended by the browser autoplay policy. */
async function ensureRunning(ctx) {
  if (ctx.state === 'suspended') {
    await ctx.resume().catch(() => {});
  }
}

// ── Tone synthesis ────────────────────────────────────────────────────────────
function playTone(cfg) {
  return new Promise(async (resolve) => {
    const ctx = getContext();
    if (!ctx) return resolve();

    await ensureRunning(ctx);

    const { freq, overtone, gain, overtoneGain, attack, decay } = cfg;
    const now = ctx.currentTime;

    const master = ctx.createGain();
    master.connect(ctx.destination);
    master.gain.setValueAtTime(0, now);
    master.gain.linearRampToValueAtTime(gain, now + attack);
    master.gain.exponentialRampToValueAtTime(0.0001, now + decay);

    const osc1 = ctx.createOscillator();
    osc1.type = 'sine';
    osc1.frequency.setValueAtTime(freq, now);
    osc1.connect(master);
    osc1.start(now);
    osc1.stop(now + decay + 0.1);

    const osc2Gain = ctx.createGain();
    osc2Gain.gain.setValueAtTime(overtoneGain, now);
    osc2Gain.connect(master);
    const osc2 = ctx.createOscillator();
    osc2.type = 'sine';
    osc2.frequency.setValueAtTime(overtone, now);
    osc2.connect(osc2Gain);
    osc2.start(now);
    osc2.stop(now + decay + 0.1);

    setTimeout(resolve, (decay + 0.15) * 1000);
  });
}

// ── MP3 fallback (classic) ────────────────────────────────────────────────────
function playMp3() {
  return new Promise((resolve) => {
    const audio = new Audio('/sounds/ding.mp3');
    let settled = false;
    const done = () => { if (!settled) { settled = true; resolve(); } };
    audio.onended = done;
    audio.onerror = done;
    audio.play().catch(done);
    setTimeout(done, 5000);
  });
}

// ── Public API ────────────────────────────────────────────────────────────────
export const DingPlayer = {
  /**
   * Call this as early as possible (ideally inside a user-gesture handler or
   * onMount). Creates the AudioContext and attempts to resume it so the first
   * real ding plays without delay.
   */
  unlock() {
    if (typeof window === 'undefined') return;
    const ctx = getContext();
    if (ctx) ctx.resume().catch(() => {});
  },

  /**
   * Play a ding variant.
   * @param {string} variant - 'gentle' | 'soft' | 'classic'
   */
  play(variant = 'gentle') {
    if (typeof window === 'undefined') return Promise.resolve();
    const cfg = VARIANTS[variant] ?? VARIANTS.gentle;
    return cfg ? playTone(cfg) : playMp3();
  },
};
