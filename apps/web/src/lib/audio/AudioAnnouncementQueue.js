import { DingPlayer } from './DingPlayer.js';

/**
 * Manages a queue of audio announcements to prevent overlapping sounds.
 * Plays a ding first, then the voice announcement.
 *
 * Voice chain (first success wins):
 *   1. Piper TTS  — GET /api/tts/announce  (server-side, works on any browser/TV)
 *   2. SpeechSynthesis API  — browser built-in fallback
 */
export class AudioAnnouncementQueue {
  /**
   * @param {object} opts
   * @param {string} [opts.apiBase]    - Base URL of the API (e.g. 'http://10.25.1.24:3001').
   * @param {string} [opts.dingVariant] - Ding sound variant: 'gentle' | 'soft' | 'classic'.
   */
  constructor({ apiBase = '', dingVariant = 'gentle' } = {}) {
    this.apiBase     = apiBase;
    this.dingVariant = dingVariant;

    this.queue = [];
    this.isPlaying = false;
    this.processedTicketIds = new Set();

    this.speechRateMultiplier = 1.0;
  }

  /**
   * Enqueue a ticket for announcement.
   * Skipped if the same ticket+timestamp was already announced.
   * @param {Object} ticket - ticket_id, ticket_code, station_name, called_at
   * @param {boolean} force - Force play even if previously processed
   */
  enqueue(ticket, force = false) {
    const runKey = `${ticket.ticket_id}_${new Date(ticket.called_at || Date.now()).getTime()}`;

    if (!force && this.processedTicketIds.has(runKey)) return;

    this.processedTicketIds.add(runKey);

    this.queue.push({
      ticketCode:  ticket.ticket_code,
      stationName: ticket.station_name || ticket.module_name || '',
      // prefix del módulo/cola (e.g. "P1", "C") para separar correctamente
      // el prefijo de la secuencia numérica al leer el turno.
      // Si no viene en el objeto, splitCode usará el fallback de últimos 2 chars.
      prefix: ticket.prefix || '',
    });

    this._processNext();
  }

  /**
   * Internal processor — pops the next announcement and plays it.
   */
  async _processNext() {
    if (this.isPlaying || this.queue.length === 0) return;

    this.isPlaying = true;
    const { ticketCode, stationName, prefix } = this.queue.shift();

    try {
      // 1. Ding
      await this._playDing();

      // 2. Short pause after ding
      await new Promise(r => setTimeout(r, 600));

      // 3. Voice — Piper TTS primero, SpeechSynthesis como fallback
      // this.apiBase puede ser '' (mismo origen) o 'http://host:port' (externo);
      // ambos son válidos: fetch(''/api/tts/...') = ruta relativa al mismo servidor.
      let voiced = false;

      if (typeof window !== 'undefined') {
        voiced = await this._playTtsEndpoint(ticketCode, stationName, prefix);
      }

      if (!voiced && typeof window !== 'undefined' && window.speechSynthesis) {
        await this._playSpeech(ticketCode, stationName, prefix);
      }
    } catch (e) {
      console.error('Error during audio announcement', e);
    } finally {
      this.isPlaying = false;
      // Short pause before next announcement
      await new Promise(r => setTimeout(r, 800));
      this._processNext();
    }
  }

  /**
   * Primary voice: fetches a WAV from the Piper TTS API endpoint and plays it.
   * Returns true on success, false on any failure (falls through to SpeechSynthesis).
   */
  /**
   * Fetches the WAV from Piper TTS API and plays it via Web Audio API (AudioContext).
   * Using fetch() + decodeAudioData instead of new Audio() works in Electron,
   * Smart TV browsers, and any Chromium regardless of CSP/codec restrictions.
   */
  async _playTtsEndpoint(ticketCode, stationName, prefix) {
    const params = new URLSearchParams({
      code:    ticketCode  || '',
      station: stationName || '',
      prefix:  prefix      || '',
    });
    const url = `${this.apiBase}/api/tts/announce?${params}`;

    try {
      const res = await fetch(url);
      if (!res.ok) {
        console.warn(`[TTS] Piper endpoint returned ${res.status} — using fallback. URL: ${url}`);
        return false;
      }

      const arrayBuffer = await res.arrayBuffer();

      // Reuse a single AudioContext per queue instance
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return false;
      if (!this._audioCtx) this._audioCtx = new AC();
      if (this._audioCtx.state === 'suspended') await this._audioCtx.resume();

      const audioBuffer = await this._audioCtx.decodeAudioData(arrayBuffer);
      const source = this._audioCtx.createBufferSource();
      source.buffer = audioBuffer;
      source.connect(this._audioCtx.destination);
      source.start();

      await new Promise((resolve) => {
        source.onended = resolve;
        setTimeout(resolve, 15000); // safety timeout
      });

      console.log('[TTS] Piper OK:', ticketCode);
      return true;
    } catch (e) {
      console.warn('[TTS] Piper error, using fallback:', e.message);
      return false;
    }
  }

  /**
   * Fallback: SpeechSynthesis API.
   * Waits for voices to load if they haven't yet (important on first page load).
   */
  _playSpeech(ticketCode, stationName, prefix) {
    return new Promise((resolve) => {
      // ── Separar prefix y secuencia ──────────────────────────────────────
      // Los tickets siempre son: prefix + secuencia con padStart(2,'0')
      // Ejemplo: "P1" + "03" = "P103"  |  "C" + "20" = "C20"
      const DIGIT_WORDS = ['cero','uno','dos','tres','cuatro','cinco','seis','siete','ocho','nueve'];
      const upper       = (ticketCode || '').trim().toUpperCase();
      const cleanPfx    = (prefix || '').toUpperCase();

      let pfx, seq;
      if (cleanPfx && upper.startsWith(cleanPfx)) {
        pfx = cleanPfx;
        seq = upper.slice(cleanPfx.length);
      } else {
        // Fallback: últimos 2 chars = secuencia
        pfx = upper.length > 2 ? upper.slice(0, -2) : upper;
        seq = upper.length > 2 ? upper.slice(-2)    : '';
      }

      // Prefix: letras quedan como letras; dígitos se convierten en palabra
      const pfxText = pfx.split('').map(c => /\d/.test(c) ? DIGIT_WORDS[+c] : c).join(' ');

      // Secuencia: cero inicial → deletrear; sin cero → número natural (browser dice "veinte", "diez")
      const seqText = seq.startsWith('0')
        ? seq.split('').map(c => DIGIT_WORDS[+c]).join(' ')
        : seq;

      const parts = [pfxText, seqText].filter(Boolean).join(', ');
      const dest  = stationName ? `Pase a ${stationName}.` : '';
      const text  = `Turno ${parts}. ${dest}`.replace(/\s{2,}/g, ' ').trim();

      const speak = () => {
        const utterance = new SpeechSynthesisUtterance(text);
        const voices    = window.speechSynthesis.getVoices();
        const esVoices  = voices.filter(v => v.lang.startsWith('es'));
        const voice     = esVoices.find(v => v.lang === 'es-DO')
                       || esVoices.find(v => v.lang === 'es-US')
                       || esVoices[0];

        if (voice) {
          utterance.voice = voice;
          utterance.lang  = voice.lang;
        } else {
          utterance.lang = 'es-ES';
        }

        utterance.rate  = 0.85 * this.speechRateMultiplier;
        utterance.pitch = 1.0;
        utterance.volume = 1.0;

        let resolved = false;
        const done = () => { if (!resolved) { resolved = true; resolve(); } };
        utterance.onend   = done;
        utterance.onerror = (e) => { console.warn('[TTS] SpeechSynthesis error:', e.error); done(); };

        window.speechSynthesis.cancel(); // clear any stuck utterance
        window.speechSynthesis.speak(utterance);
        setTimeout(done, 15000);
      };

      const voices = window.speechSynthesis.getVoices();
      if (voices.length > 0) {
        speak();
      } else {
        // Voices not loaded yet — wait for the event (max 3s)
        let fired = false;
        const onVoices = () => {
          if (fired) return;
          fired = true;
          window.speechSynthesis.removeEventListener('voiceschanged', onVoices);
          speak();
        };
        window.speechSynthesis.addEventListener('voiceschanged', onVoices);
        setTimeout(() => { if (!fired) { fired = true; speak(); } }, 3000);
      }
    });
  }

  /**
   * Plays the configured ding variant via DingPlayer.
   */
  _playDing() {
    return DingPlayer.play(this.dingVariant || 'gentle').catch(() => {});
  }
}

// Export a singleton instance strictly for client-side use
export const audioQueue = new AudioAnnouncementQueue();
