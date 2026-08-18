# ──────────────────────────────────────────────────────────────────────────────
# Production API server (serves API + precompiled web UI)
#
# El UI (apps/web/build) llega ya compilado en este repo — no se distribuye ni
# se compila el codigo fuente del frontend aqui. Se actualiza vía
# scripts/release-medica.ps1 en flow-connected.
#
# Base Debian (glibc), no Alpine: el binario Piper TTS vendorizado (ver mas
# abajo) es un release oficial de glibc — necesita /lib64/ld-linux-x86-64.so.2,
# que no existe en musl/Alpine. Correr esto sobre Alpine haria que Piper nunca
# arrancara (independientemente de si la descarga de red hubiese funcionado).
# ──────────────────────────────────────────────────────────────────────────────
FROM node:20-slim AS production

WORKDIR /app

# Copy package manifests (api workspace only — apps/web has no package.json)
COPY package.json package-lock.json ./
COPY apps/api/package.json ./apps/api/

# Install production deps only
RUN npm ci --omit=dev

# Copy API source and database scripts
COPY apps/api/src ./apps/api/src
COPY apps/api/db  ./apps/api/db

# Copy precompiled web UI (committed to this repo, see apps/web/build/)
COPY apps/web/build ./apps/web/build

# ── Paquete de voz Piper TTS (vendorizado en este repo) ──────────────────────
# El binario Linux x86_64 de Piper + el modelo de voz en español
# (es_ES-davefx-medium) viven directamente en apps/api/tts/{bin,models} de
# este repo — no se descargan en cada build. Esto evita que el build del
# cliente dependa de acceso a GitHub/HuggingFace (causa raíz de un bug donde,
# sin Piper, el board caía al speechSynthesis del navegador y leía los
# anuncios con voz en inglés). El release original no preserva symlinks al
# extraerse en Windows, así que se recrean aquí, nativamente en Linux.
COPY apps/api/tts/bin    ./apps/api/tts/bin
COPY apps/api/tts/models ./apps/api/tts/models
RUN cd apps/api/tts/bin && \
    ln -sf libpiper_phonemize.so.1.2.0 libpiper_phonemize.so.1 && \
    ln -sf libpiper_phonemize.so.1     libpiper_phonemize.so && \
    ln -sf libespeak-ng.so.1.52.0.1    libespeak-ng.so.1 && \
    ln -sf libespeak-ng.so.1           libespeak-ng.so && \
    ln -sf libonnxruntime.so.1.14.1    libonnxruntime.so && \
    chmod +x piper piper_phonemize espeak-ng

# Create runtime directories
RUN mkdir -p apps/api/cache/tts apps/api/tts/tmp apps/api/media/boards

# ── Run as a non-root user ───────────────────────────────────────────────────
# The official node images (slim included) already ship a `node` user at a
# fixed uid/gid 1000 — reuse it instead of creating a new one (deterministic
# across rebuilds, needed to `chown` the tts_cache/board_media named volumes
# to match on deploy).
RUN chown -R node:node /app

USER node

EXPOSE 3001

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3001

CMD ["node", "apps/api/src/server.js"]
