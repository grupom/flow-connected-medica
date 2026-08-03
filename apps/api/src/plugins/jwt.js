'use strict';

const fp = require('fastify-plugin');
const env = require('../config/env');

module.exports = fp(async function jwtPlugin(fastify) {
    await fastify.register(require('@fastify/cookie'));

    // --- Access token (short-lived, 15m) ---
    // `cookie` makes accessVerify() fall back to reading the httpOnly cookie
    // when there's no Authorization header — the token itself is never
    // returned in a JSON body or readable from JS (see routes/auth/index.js).
    await fastify.register(require('@fastify/jwt'), {
        secret: env.JWT_SECRET,
        namespace: 'access',
        jwtVerify: 'accessVerify',
        jwtSign: 'accessSign',
        sign: { expiresIn: env.JWT_ACCESS_EXPIRY },
        cookie: { cookieName: 'cq_access_token', signed: false },
    });

    // --- Refresh token (long-lived, 7d) ---
    await fastify.register(require('@fastify/jwt'), {
        secret: env.JWT_REFRESH_SECRET,
        namespace: 'refresh',
        jwtVerify: 'refreshVerify',
        jwtSign: 'refreshSign',
        sign: { expiresIn: env.JWT_REFRESH_EXPIRY },
        cookie: { cookieName: 'cq_refresh_token', signed: false },
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

    // Route-options object for ADMIN-only endpoints. Usage: pass it directly
    // as route options, or spread it (`...fastify.adminOnly`) alongside a
    // `schema` key. Was previously copy-pasted into every admin/* route file.
    fastify.decorate('adminOnly', {
        preHandler: [
            fastify.authenticate,
            async function requireAdmin(request, reply) {
                const roles = request.user?.role_codes ?? [];
                if (!roles.includes('ADMIN')) {
                    return reply.code(403).send({ error: 'Forbidden', message: 'Se requiere rol ADMIN' });
                }
            },
        ],
    });
});
