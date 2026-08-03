'use strict';

const fp = require('fastify-plugin');
const env = require('../config/env');

// RFC1918 private ranges + loopback. Gated behind CORS_TRUST_LAN (see
// config/env.js) — off by default, since trusting any private-network host
// means any device on the same LAN as the server, not just the clinic's own
// equipment, can make credentialed requests. Most installs don't need this:
// in production the UI and API are served same-origin (the same-port check
// below already covers that), and local dev is covered by the exact
// CORS_ORIGIN match. A site that genuinely needs an extra origin/subnet
// should list it explicitly via CORS_ORIGIN or CORS_SUBNETS instead of
// opting into this wildcard.
function isPrivateNetworkHost(hostname) {
    if (hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '::1') return true;
    if (/^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(hostname)) return true;
    if (/^192\.168\.\d{1,3}\.\d{1,3}$/.test(hostname)) return true;
    if (/^172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}$/.test(hostname)) return true;
    return false;
}

module.exports = fp(async function corsPlugin(fastify) {
    await fastify.register(require('@fastify/cors'), {
        origin: function (origin, callback) {
            // Same-origin / server-to-server (no Origin header)
            if (!origin) return callback(null, true);

            // Exact match
            if (env.CORS_ORIGIN.includes(origin)) return callback(null, true);

            let url;
            try {
                url = new URL(origin);
            } catch (_) {
                return callback(new Error(`CORS: origin not allowed — ${origin}`), false);
            }

            // Same-server origin: browser requests from a page served by this same
            // server (e.g. ES module imports) always carry Origin even when same-origin.
            // Allow when the origin's port matches the server port.
            const originPort = url.port || (url.protocol === 'https:' ? '443' : '80');
            if (originPort === String(env.PORT)) return callback(null, true);

            // Any private-network host — opt-in only, see isPrivateNetworkHost() above.
            if (env.CORS_TRUST_LAN && isPrivateNetworkHost(url.hostname)) return callback(null, true);

            // Explicit-prefix allow-list — the recommended way for a site to trust
            // an extra origin/subnet without opting into the whole LAN.
            if (env.CORS_SUBNETS.length) {
                const host = origin.replace(/^https?:\/\//, '');
                if (env.CORS_SUBNETS.some((subnet) => host.startsWith(subnet))) {
                    return callback(null, true);
                }
            }

            callback(new Error(`CORS: origin not allowed — ${origin}`), false);
        },
        credentials: true,
        methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
        allowedHeaders: ['Content-Type', 'Authorization'],
    });
});
