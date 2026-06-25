'use strict';

const { spawn, execFile } = require('child_process');
const crypto    = require('crypto');
const fs        = require('fs');
const path      = require('path');

const IS_WIN    = process.platform === 'win32';
const PIPER_BIN = path.join(__dirname, '../../../tts/bin', IS_WIN ? 'piper.exe' : 'piper');
const MODEL     = path.join(__dirname, '../../../tts/models/es_ES-davefx-medium.onnx');
const BIN_DIR   = path.join(__dirname, '../../../tts/bin');
const CACHE_DIR = path.join(__dirname, '../../../cache/tts');

// Nombres en español para cada dígito (usado al deletrear secuencias con cero inicial)
const DIGIT_WORDS_ES = ['cero', 'uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve'];

/**
 * Separa el código del ticket en { prefix, seq } (secuencia numérica).
 *
 * Regla del sistema: los tickets siempre se generan como  prefix + padStart(2,'0')
 * Ejemplos: "P1" + "03" = "P103", "C" + "20" = "C20", "CF" + "02" = "CF02"
 *
 * Si se conoce el prefix → se usa directamente.
 * Fallback → los últimos 2 caracteres son siempre la secuencia.
 */
function splitCode(upper, knownPrefix) {
    if (knownPrefix && upper.startsWith(knownPrefix)) {
        return { prefix: knownPrefix, seq: upper.slice(knownPrefix.length) };
    }
    // Fallback: secuencia = últimos 2 chars, prefix = resto
    return {
        prefix: upper.length > 2 ? upper.slice(0, -2) : upper,
        seq:    upper.length > 2 ? upper.slice(-2)    : '',
    };
}

/**
 * Devuelve el texto TTS para un carácter del prefix:
 *  • Dígito → nombre en español ("1" → "uno")
 *  • Letra  → la letra sola (Piper la pronuncia como "pe", "ce", etc.)
 */
function spelledChar(ch) {
    return /\d/.test(ch) ? DIGIT_WORDS_ES[+ch] : ch;
}

/**
 * Builds the Spanish announcement text from a ticket code + station name.
 *
 * @param {string} code        - e.g. "P103", "C20", "CF02"
 * @param {string} stationName - e.g. "Consultorio Puerta 1"
 * @param {string} [prefix]    - prefix conocido del módulo, e.g. "P1", "C", "CF"
 *
 * Examples:
 *   ("P103", "Consultorio Puerta 1", "P1") → "Turno P uno, cero tres. Favor dirigirse a Consultorio Puerta 1."
 *   ("C20",  "Consultorio 1",        "C")  → "Turno C, veinte. Favor dirigirse a Consultorio 1."
 *   ("C01",  "Consultorio 1",        "C")  → "Turno C, cero uno. Favor dirigirse a Consultorio 1."
 *   ("CF02", "Consulta Familiar",    "CF") → "Turno C F, cero dos. Favor dirigirse a Consulta Familiar."
 */
function buildText(code, stationName, prefix) {
    const upper      = (code || '').trim().toUpperCase();
    if (!upper) return '';

    const { prefix: pfx, seq } = splitCode(upper, (prefix || '').trim().toUpperCase());

    // Prefix: cada carácter separado por espacio; los dígitos se convierten en palabra
    const prefixText = pfx.split('').map(spelledChar).join(' ');

    // Secuencia: si empieza con 0 → deletrear dígito a dígito; si no → número natural
    // (Piper lee "20" como "veinte", "10" como "diez", etc.)
    const seqText = seq.startsWith('0')
        ? seq.split('').map(spelledChar).join(' ')
        : seq;

    const parts = [prefixText, seqText].filter(Boolean).join(', ');
    const dest  = stationName ? `Favor dirigirse a ${stationName.trim()}.` : '';
    return `Turno ${parts}. ${dest}`.replace(/\s{2,}/g, ' ').trim();
}

/**
 * Returns a readable WAV stream for the announcement.
 * Generates via Piper TTS (neural) with fallback to Windows SAPI.
 * Caches on disk so identical announcements are served instantly.
 */
async function synthesize(code, stationName, prefix) {
    const text      = buildText(code, stationName, prefix);
    const hash      = crypto.createHash('sha1').update(text).digest('hex');
    const cachePath = path.join(CACHE_DIR, `${hash}.wav`);

    if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });

    if (!fs.existsSync(cachePath)) {
        await _generate(text, cachePath);
    }

    return fs.createReadStream(cachePath);
}

/**
 * Generate a WAV file for the given text.
 * Tries Piper first; falls back to Windows SAPI on failure.
 */
async function _generate(text, outputPath) {
    // ── 1. Piper (neural, high quality) ────────────────────────────────────
    if (fs.existsSync(PIPER_BIN)) {
        try {
            await runPiper(text, outputPath);
            return; // success
        } catch (err) {
            // Piper crashed (e.g. CPU lacks AVX2 for ONNX Runtime) — try SAPI
            console.warn('[TTS] Piper failed, falling back to Windows SAPI:', err.message);
        }
    } else {
        console.warn('[TTS] Piper binary not found, falling back to Windows SAPI');
    }

    // ── 2. Windows SAPI fallback (built-in, no external dependencies) ──────
    if (IS_WIN) {
        await runSapi(text, outputPath);
        return;
    }

    // Non-Windows with no Piper → hard error
    throw Object.assign(
        new Error('TTS unavailable: Piper not found and SAPI is Windows-only. Run: node scripts/setup-piper.js'),
        { statusCode: 503 }
    );
}

// ── Piper ─────────────────────────────────────────────────────────────────────

function runPiper(text, outputPath) {
    return new Promise((resolve, reject) => {
        const proc = spawn(PIPER_BIN, [
            '--model',       MODEL,
            '--output_file', outputPath,
            '--espeak-data', path.join(BIN_DIR, 'espeak-ng-data'),
        ], {
            // cwd must be BIN_DIR so Windows finds the bundled DLLs
            cwd: BIN_DIR,
        });

        let stderr = '';
        proc.stderr.on('data', d => { stderr += d.toString(); });

        proc.stdin.write(text, 'utf8');
        proc.stdin.end();

        proc.on('close', code => {
            if (code === 0) return resolve();
            reject(new Error(`piper exited ${code}: ${stderr.slice(0, 300)}`));
        });
        proc.on('error', err => {
            reject(new Error(`Failed to start piper: ${err.message}`));
        });
    });
}

// ── Windows SAPI ──────────────────────────────────────────────────────────────

/**
 * Generate a WAV file via Windows Speech API (System.Speech).
 * Uses the first installed Spanish voice; falls back to system default.
 * @param {string} text
 * @param {string} outputPath  absolute path to the output .wav file
 */
function runSapi(text, outputPath) {
    return new Promise((resolve, reject) => {
        // Encode text as base64 UTF-16LE to handle ó, é, ñ, ú safely
        const b64 = Buffer.from(text, 'utf16le').toString('base64');
        // Normalise output path for PowerShell (backslashes, no quotes needed with b64)
        const wavPath = outputPath.replace(/\//g, '\\');

        const script = [
            'Add-Type -AssemblyName System.Speech;',
            '$s = New-Object System.Speech.Synthesis.SpeechSynthesizer;',
            `$t = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('${b64}'));`,
            `$v = $s.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -like 'es*' };`,
            `if ($v.Count -gt 0) { $s.SelectVoice($v[0].VoiceInfo.Name) };`,
            '$s.Rate = -2;',
            `$s.SetOutputToWaveFile('${wavPath}');`,
            '$s.Speak($t);',
            '$s.Dispose();',
        ].join(' ');

        execFile(
            'powershell',
            ['-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-Command', script],
            { timeout: 30000, windowsHide: true },
            (err, stdout, stderr) => {
                if (err) {
                    return reject(new Error(`SAPI failed: ${err.message} | ${stderr}`));
                }
                if (!fs.existsSync(outputPath)) {
                    return reject(new Error('SAPI ran but no WAV file was created'));
                }
                resolve();
            }
        );
    });
}

module.exports = { synthesize, buildText };
