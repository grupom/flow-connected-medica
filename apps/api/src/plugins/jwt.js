'use strict';

const fp = require('fastify-plugin');
const env = require('../config/env');

module.exports = fp(async function jwtPlugin(fastify) {
    await fastify.register(require('@fastify/cookie'));

    // --- Access token (short-lived, 15m) ---
    await fastify.register(require('@fastify/jwt'), {
        secret: env.JWT_SECRET,
        namespace: 'access',
        jwtVerify: 'accessVerify',
        jwtSign: 'accessSign',
        sign: { expiresIn: env.JWT_ACCESS_EXPIRY },
    });

    // --- Refresh token (long-lived, 7d) ---
    await fastify.register(require('@fastify/jwt'), {
        secret: env.JWT_REFRESH_SECRET,
        namespace: 'refresh',
        jwtVerify: 'refreshVerify',
        jwtSign: 'refreshSign',
        sign: { expiresIn: env.JWT_REFRESH_EXPIRY },
    });

    // Middleware decorator for protected routes
    fastify.decorate('authenticate', async function (request, reply) {
        try {
            await request.accessVerify();
        } catch {
            return reply.code(401).send({ error: 'Unauthorized', message: 'Invalid or expired access token' });
        }
    });

    // Middleware decorator for refresh endpoint
    fastify.decorate('authenticateRefresh', async function (request, reply) {
        try {
            await request.refreshVerify();
        } catch {
            return reply.code(401).send({ error: 'Unauthorized', message: 'Invalid or expired refresh token' });
        }
    });
});
