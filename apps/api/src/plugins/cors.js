'use strict';

const fp = require('fastify-plugin');
const env = require('../config/env');

// RFC1918 private ranges + loopback. This app is deployed on-prem inside each
// client's own LAN, where the server/browser IP and dev-server port vary per
// site (and can change on DHCP renewal). Trusting any private-network origin —
// an explicit, deliberate choice for this on-prem deployment model — means
// CORS never needs to be reconfigured per site or per port.
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

            // Any private-network host — see isPrivateNetworkHost() above.
            if (isPrivateNetworkHost(url.hostname)) return callback(null, true);

            // Legacy explicit-prefix allow-list, kept for anything outside RFC1918
            // (e.g. an internal DNS name) that still needs an explicit opt-in.
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
