# ──────────────────────────────────────────────────────────────────────────────
# Stage 1 — Build SvelteKit web UI
# ──────────────────────────────────────────────────────────────────────────────
FROM node:20-alpine AS web-builder

WORKDIR /build

# Copy package manifests for layer caching
COPY package.json package-lock.json ./
COPY apps/web/package.json ./apps/web/
COPY apps/api/package.json ./apps/api/

# Install all deps (dev tools required for the SvelteKit build)
RUN npm ci

# Copy web source and compile
COPY apps/web ./apps/web

# Empty PUBLIC_API_URL = same-origin relative paths (/api/...) — no CORS needed
ENV PUBLIC_API_URL=
RUN npm run build:web

# ──────────────────────────────────────────────────────────────────────────────
# Stage 2 — Production API server (serves API + compiled web UI)
# ──────────────────────────────────────────────────────────────────────────────
FROM node:20-alpine AS production

WORKDIR /app

# Install wget + tar for Piper TTS download
RUN apk add --no-cache wget tar

# Copy package manifests (both workspaces needed for monorepo hoisting)
COPY package.json package-lock.json ./
COPY apps/api/package.json ./apps/api/
COPY apps/web/package.json ./apps/web/

# Install production deps only — apps/web has no production deps so nothing extra is added
RUN npm ci --omit=dev

# Copy API source and database scripts
COPY apps/api/src ./apps/api/src
COPY apps/api/db  ./apps/api/db

# Copy compiled web UI from Stage 1
COPY --from=web-builder /build/apps/web/build ./apps/web/build

# ── Download Piper TTS (Linux x86_64) ────────────────────────────────────────
# Falls back gracefully to browser SpeechSynthesis if the download fails.
RUN mkdir -p apps/api/tts/bin apps/api/tts/models && \
    wget -q \
      "https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_linux_x86_64.tar.gz" \
      -O /tmp/piper.tar.gz && \
    tar -xzf /tmp/piper.tar.gz -C /tmp && \
    cp -r /tmp/piper/. apps/api/tts/bin/ && \
    chmod +x apps/api/tts/bin/piper && \
    rm -rf /tmp/piper /tmp/piper.tar.gz && \
    wget -q \
      "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/davefx/medium/es_ES-davefx-medium.onnx" \
      -O apps/api/tts/models/es_ES-davefx-medium.onnx && \
    wget -q \
      "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/es/es_ES/davefx/medium/es_ES-davefx-medium.onnx.json" \
      -O apps/api/tts/models/es_ES-davefx-medium.onnx.json || \
    echo "WARNING: Piper TTS download failed. Browser SpeechSynthesis will be used as fallback."

# Create runtime directories
RUN mkdir -p apps/api/cache/tts apps/api/tts/tmp apps/api/media/boards

# ── Run as a non-root user ───────────────────────────────────────────────────
# node:20-alpine already ships a `node` user at a fixed uid/gid 1000 — reuse it
# instead of creating a new one (deterministic across rebuilds, needed to
# `chown` the tts_cache/board_media named volumes to match on deploy).
RUN chown -R node:node /app

USER node

EXPOSE 3001

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3001

CMD ["node", "apps/api/src/server.js"]
