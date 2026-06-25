'use strict';

const { loginSchema, refreshSchema, logoutSchema } = require('./schemas');
const svc = require('./service');
const env = require('../../config/env');

module.exports = async function authRoutes(fastify) {
    // ── POST /api/auth/login ──────────────────────────────────────────────────
    fastify.post('/login', loginSchema, async (request, reply) => {
        const { login, password } = request.body;

        const user = await svc.findUserForLogin(login);
        if (!user) {
            return reply.code(401).send({ error: 'Unauthorized', message: 'Invalid credentials' });
        }
        if (!user.password_hash) {
            return reply.code(403).send({ error: 'Forbidden', message: 'User has no password set' });
        }

        const passOk = await svc.verifyPassword(password, user.password_hash);
        if (!passOk) {
            return reply.code(401).send({ error: 'Unauthorized', message: 'Invalid credentials' });
        }

        const payload = {
            user_id: user.user_id,
            username: user.username,
            role_codes: user.role_codes || [],
        };

        // Sign access token
        const accessToken = await reply.accessSign(payload);

        // Generate opaque refresh token string + sign JWT refresh
        const refreshRaw = svc.generateRefreshTokenString();
        const refreshToken = await reply.refreshSign({ ...payload, jti: refreshRaw });

        // Compute expiry (7d from now)
        const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
        await svc.storeRefreshToken(user.user_id, refreshRaw, expiresAt);

        // Update last login
        await svc.touchLastLogin(user.user_id);

        return reply.code(200).send({
            accessToken,
            refreshToken,
            user: {
                user_id: user.user_id,
                username: user.username,
                display_name: user.display_name,
                email: user.email,
                phone: user.phone,
                role_codes: user.role_codes || [],
            },
        });
    });

    // ── POST /api/auth/refresh ────────────────────────────────────────────────
    fastify.post('/refresh', refreshSchema, async (request, reply) => {
        const { refreshToken } = request.body;

        // Verify JWT signature first
        let decoded;
        try {
            decoded = await request.refreshVerify({ onlyCookie: false, complete: false, token: refreshToken });
        } catch {
            return reply.code(401).send({ error: 'Unauthorized', message: 'Invalid refresh token' });
        }

        // Check DB (not revoked, not expired)
        const stored = await svc.getStoredRefreshToken(decoded.jti);
        if (!stored) {
            return reply.code(401).send({ error: 'Unauthorized', message: 'Refresh token revoked or expired' });
        }

        // Rotate: revoke old, issue new
        await svc.revokeRefreshToken(decoded.jti);

        const payload = {
            user_id: stored.user_id,
            username: stored.username,
            role_codes: stored.role_codes || [],
        };

        const accessToken = await reply.accessSign(payload);
        const refreshRaw = svc.generateRefreshTokenString();
        const newRefreshToken = await reply.refreshSign({ ...payload, jti: refreshRaw });
        const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
        await svc.storeRefreshToken(stored.user_id, refreshRaw, expiresAt);

        return reply.code(200).send({
            accessToken,
            refreshToken: newRefreshToken,
            user: {
                user_id: stored.user_id,
                username: stored.username,
                display_name: stored.display_name,
                email: stored.email,
                phone: stored.phone,
                role_codes: stored.role_codes || [],
            },
        });
    });

    // ── POST /api/auth/logout ─────────────────────────────────────────────────
    fastify.post('/logout', logoutSchema, async (request, reply) => {
        const { refreshToken } = request.body;
        try {
            const decoded = await request.refreshVerify({ onlyCookie: false, complete: false, token: refreshToken });
            if (decoded?.jti) {
                await svc.revokeRefreshToken(decoded.jti);
            }
        } catch {
            // Ignore invalid tokens on logout — just ack
        }
        return reply.code(200).send({ ok: true });
    });
};
