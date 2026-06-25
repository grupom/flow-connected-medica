'use strict';

/**
 * setup-piper.js — One-time setup: downloads piper binary + Spanish voice model
 *
 * Run once from apps/api/:
 *   node scripts/setup-piper.js
 *
 * Downloads:
 *   tts/bin/piper         (or piper.exe on Windows)
 *   tts/models/es_ES-davefx-medium.onnx
 *   tts/models/es_ES-davefx-medium.onnx.json
 */

const https    = require('https');
const fs       = require('fs');
const path     = require('path');
const zlib     = require('zlib');
const { execSync } = require('child_process');

const PIPER_VERSION = '2023.11.14-2';
const BASE_URL = `https://github.com/rhasspy/piper/releases/download/${PIPER_VERSION}`;

const PLATFORM_MAP = {
    linux:  { archive: 'piper_linux_x86_64.tar.gz',   binary: 'piper/piper',     ext: ''    },
    win32:  { archive: 'piper_windows_amd64.zip',      binary: 'piper/piper.exe', ext: '.exe'},
    darwin: { archive: 'piper_macos_x64.tar.gz',       binary: 'piper/piper',     ext: ''    },
};

const MODEL_BASE = 'https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/davefx/medium';
const MODEL_FILES = [
    'es_ES-davefx-medium.onnx',
    'es_ES-davefx-medium.onnx.json',
];

const ROOT      = path.join(__dirname, '..');
const BIN_DIR   = path.join(ROOT, 'tts', 'bin');
const MODEL_DIR = path.join(ROOT, 'tts', 'models');
const TMP_DIR   = path.join(ROOT, 'tts', 'tmp');

// ── helpers ──────────────────────────────────────────────────────────────────

function mkdirs(...dirs) {
    for (const d of dirs) fs.mkdirSync(d, { recursive: true });
}

function download(url, dest) {
    return new Promise((resolve, reject) => {
        console.log(`  ↓ ${url}`);
        const file = fs.createWriteStream(dest);
        const get = (u) => {
            https.get(u, (res) => {
                if (res.statusCode === 301 || res.statusCode === 302) {
                    return get(res.headers.location);
                }
                if (res.statusCode !== 200) {
                    return reject(new Error(`HTTP ${res.statusCode} — ${u}`));
                }
                res.pipe(file);
                file.on('finish', () => file.close(resolve));
            }).on('error', reject);
        };
        get(url);
    });
}

function extractTarGz(archive, destDir) {
    execSync(`tar -xzf "${archive}" -C "${destDir}"`);
}

function extractZip(archive, destDir) {
    // Use PowerShell on Windows (available by default)
    execSync(`powershell -Command "Expand-Archive -Path '${archive}' -DestinationPath '${destDir}' -Force"`);
}

/**
 * Copy a directory tree recursively (src → dest).
 * Creates dest and subdirectories as needed.
 */
function _copyDirRecursive(src, dest) {
    fs.mkdirSync(dest, { recursive: true });
    for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
        const srcPath  = path.join(src,  entry.name);
        const destPath = path.join(dest, entry.name);
        if (entry.isDirectory()) {
            _copyDirRecursive(srcPath, destPath);
        } else {
            fs.copyFileSync(srcPath, destPath);
        }
    }
}

// ── main ─────────────────────────────────────────────────────────────────────

async function main() {
    const platform = process.platform;
    const info = PLATFORM_MAP[platform];
    if (!info) {
        console.error(`Unsupported platform: ${platform}`);
        process.exit(1);
    }

    mkdirs(BIN_DIR, MODEL_DIR, TMP_DIR);

    const binaryName = `piper${info.ext}`;
    const binaryDest = path.join(BIN_DIR, binaryName);

    // ── 1. Download + extract piper binary ───────────────────────────────────
    if (fs.existsSync(binaryDest)) {
        console.log(`✅  Piper binary already exists: ${binaryDest}`);
    } else {
        console.log(`\n📦  Downloading piper binary (${info.archive})…`);
        const archivePath = path.join(TMP_DIR, info.archive);
        await download(`${BASE_URL}/${info.archive}`, archivePath);

        console.log('    Extracting…');
        if (info.archive.endsWith('.tar.gz')) {
            extractTarGz(archivePath, TMP_DIR);
        } else {
            extractZip(archivePath, TMP_DIR);
        }

        // Copy ALL files from the extracted piper/ folder to BIN_DIR
        // (Windows needs piper.exe + DLLs + espeak-ng-data/ in the same directory)
        const extractedDir = path.join(TMP_DIR, 'piper');
        _copyDirRecursive(extractedDir, BIN_DIR);
        if (platform !== 'win32') fs.chmodSync(binaryDest, 0o755);

        fs.rmSync(archivePath, { force: true });
        console.log(`✅  Piper binary ready: ${binaryDest}`);
    }

    // ── 2. Download voice model ───────────────────────────────────────────────
    console.log('\n🎙️   Downloading Spanish voice model (es_ES-davefx-medium)…');
    for (const file of MODEL_FILES) {
        const dest = path.join(MODEL_DIR, file);
        if (fs.existsSync(dest)) {
            console.log(`✅  Already exists: ${file}`);
            continue;
        }
        await download(`${MODEL_BASE}/${file}`, dest);
        console.log(`✅  ${file}`);
    }

    // ── 3. Cleanup tmp ────────────────────────────────────────────────────────
    fs.rmSync(TMP_DIR, { recursive: true, force: true });

    console.log('\n🎉  Piper TTS setup complete!');
    console.log(`    Binary : ${binaryDest}`);
    console.log(`    Model  : ${path.join(MODEL_DIR, MODEL_FILES[0])}`);
    console.log('\n    Test with:');
    console.log(`    echo "Turno C, 01. Favor dirigirse a Consultorio 1." | "${binaryDest}" --model "${path.join(MODEL_DIR, MODEL_FILES[0])}" --output_file test.wav`);
    console.log('    (then play test.wav)\n');
}

main().catch(e => { console.error('Setup failed:', e.message); process.exit(1); });
