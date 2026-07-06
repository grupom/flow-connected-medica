'use strict';

require('dotenv').config();

const path = require('path');
const fs   = require('fs');

const fastify = require('fastify')({ logger: { level: process.env.LOG_LEVEL || 'info' } });
const env = require('./config/env');

// Ruta al build del UI: <raíz>/apps/web/build
// __dirname = apps/api/src  →  ../../web/build = apps/web/build
const WEB_DIST = process.env.WEB_DIST || path.join(__dirname, '..', '..', 'web', 'build');

async function buildApp() {
    // ── Plugins ──────────────────────────────────────────────────────────────
    await fastify.register(require('./plugins/errorHandler'));
    await fastify.register(require('./plugins/cors'));
    await fastify.register(require('./plugins/rateLimit'));
    await fastify.register(require('./plugins/jwt'));
    await fastify.register(require('@fastify/multipart'), {
        limits: { fileSize: 100 * 1024 * 1024, files: 20 }, // per-route validation below is stricter per media type
    });

    // ── Health check ─────────────────────────────────────────────────────────
    fastify.get('/health', async () => ({ ok: true, ts: new Date().toISOString() }));

    // ── Auth routes  /api/auth ────────────────────────────────────────────────
    await fastify.register(require('./routes/auth/index'), { prefix: '/api/auth' });

    // ── Admin routes /api/admin ───────────────────────────────────────────────
    await fastify.register(require('./routes/admin/users/index'), { prefix: '/api/admin/users' });
    await fastify.register(require('./routes/admin/users/roles'), { prefix: '/api/admin/users' });
    await fastify.register(require('./routes/admin/roles/index'), { prefix: '/api/admin/roles' });
    await fastify.register(require('./routes/admin/modules/index'), { prefix: '/api/admin/modules' });
    await fastify.register(require('./routes/admin/stations/index'), { prefix: '/api/admin/stations' });
    await fastify.register(require('./routes/admin/stations/users'), { prefix: '/api/admin/stations' });
    await fastify.register(require('./routes/admin/queueSettings/index'), { prefix: '/api/admin/queue-settings' });
    await fastify.register(require('./routes/admin/boards/index'), { prefix: '/api/admin/boards' });
    await fastify.register(require('./routes/admin/boards/stations'), { prefix: '/api/admin/boards' });
    await fastify.register(require('./routes/admin/boards/media'), { prefix: '/api/admin/boards' });
    await fastify.register(require('./routes/admin/metrics/index'), { prefix: '/api/admin/metrics' });
    await fastify.register(require('./routes/admin/reports/index'), { prefix: '/api/admin/reports' });
    await fastify.register(require('./routes/admin/kiosks/index'), { prefix: '/api/admin/kiosks' });
    await fastify.register(require('./routes/admin/daily-close/index'), { prefix: '/api/admin/daily-close' });
    await fastify.register(require('./routes/admin/settings/index'), { prefix: '/api/admin/settings' });

    // ── Queue operations /api/queue ───────────────────────────────────────────
    await fastify.register(require('./routes/queue/index'), { prefix: '/api/queue' });

    // ── Profile /api/profile ──────────────────────────────────────────────────
    await fastify.register(require('./routes/profile/index'), { prefix: '/api/profile' });

    // ── My Stations /api/my-stations ──────────────────────────────────────────
    await fastify.register(require('./routes/stations/index'), { prefix: '/api/my-stations' });

    // ── Public settings /api/settings ────────────────────────────────────────
    await fastify.register(require('./routes/settings/index'), { prefix: '/api/settings' });

    // ── Display board snapshot /api/boards ────────────────────────────────────
    await fastify.register(require('./routes/boards/index'), { prefix: '/api/boards' });

    // ── Kiosk APIs /api/kiosk ─────────────────────────────────────────────────
    await fastify.register(require('./routes/kiosk/index'), { prefix: '/api/kiosk' });

    // ── TTS (Piper offline) /api/tts ──────────────────────────────────────────
    await fastify.register(require('./routes/tts/index'), { prefix: '/api/tts' });

    // ── Board ad media (público, sin auth — la TV no inicia sesión) ────────────
    // Registrado con @fastify/static para soportar Range requests (seek de <video>).
    const MEDIA_ROOT = path.join(__dirname, '..', 'media', 'boards');
    fs.mkdirSync(MEDIA_ROOT, { recursive: true });
    await fastify.register(require('@fastify/static'), {
        root: MEDIA_ROOT,
        prefix: '/media/boards/',
        decorateReply: false, // evita chocar con la decoración de reply.sendFile del SPA
        cacheControl: true,
        maxAge: '1d',
        immutable: true,
    });

    // ── Web UI (SPA estático) ─────────────────────────────────────────────────
    // Sirve los archivos compilados de SvelteKit desde apps/web/build/.
    // Debe registrarse DESPUÉS de todas las rutas /api para que no interfiera.
    const hasWebUI = fs.existsSync(path.join(WEB_DIST, 'index.html'));

    if (hasWebUI) {
        await fastify.register(require('@fastify/static'), {
            root: WEB_DIST,
            prefix: '/',
            decorateReply: true,
        });
        fastify.log.info(`Web UI → ${WEB_DIST}`);
    } else {
        fastify.log.warn(
            `Web UI no encontrado en "${WEB_DIST}". ` +
            `Ejecuta: npm run build --workspace=apps/web`
        );
    }

    // ── Fallback SPA ──────────────────────────────────────────────────────────
    // Rutas no encontradas:
    //   • /api/*  → 404 JSON  (la ruta de API no existe)
    //   • resto   → index.html (el router de SvelteKit toma el control en el cliente)
    fastify.setNotFoundHandler(async (request, reply) => {
        if (request.url.startsWith('/api/') || request.url === '/health') {
            return reply.code(404).send({
                statusCode: 404,
                error: 'Not Found',
                message: `Route ${request.method}:${request.url} not found`,
            });
        }
        if (hasWebUI) {
            return reply.sendFile('index.html');
        }
        return reply.code(404).send({ statusCode: 404, error: 'Not Found' });
    });

    return fastify;
}

async function start() {
    try {
        const app = await buildApp();
        await app.listen({ port: env.PORT, host: env.HOST });
        console.log(`\n✅  ClinicQueue API running → http://${env.HOST}:${env.PORT}\n`);
    } catch (err) {
        console.error('Fatal startup error:', err);
        process.exit(1);
    }
}

start();

