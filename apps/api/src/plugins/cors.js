'use strict';

const fp = require('fastify-plugin');
const env = require('../config/env');

module.exports = fp(async function corsPlugin(fastify) {
    await fastify.register(require('@fastify/cors'), {
        origin: function (origin, callback) {
            // Same-origin / server-to-server (no Origin header)
            if (!origin) return callback(null, true);

            // Exact match
            if (env.CORS_ORIGIN.includes(origin)) return callback(null, true);

            // Same-server origin: browser requests from a page served by this same
            // server (e.g. ES module imports) always carry Origin even when same-origin.
            // Allow when the origin's port matches the server port.
            try {
                const originPort = new URL(origin).port || (origin.startsWith('https') ? '443' : '80');
                if (originPort === String(env.PORT)) return callback(null, true);
            } catch (_) {}

            // Subnet prefix match — extracts host from origin (strips protocol)
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
