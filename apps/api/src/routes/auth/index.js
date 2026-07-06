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

        // Duration depends on admin-configured settings and whether this
        // account is bound to a kiosk (see computeSessionDurations).
        const durations = await svc.computeSessionDurations(user.user_id);

        // Sign access token
        const accessToken = await reply.accessSign(payload, { expiresIn: durations.accessExpiresIn });

        // Generate opaque refresh token string + sign JWT refresh
        const refreshRaw = svc.generateRefreshTokenString();
        const refreshToken = await reply.refreshSign({ ...payload, jti: refreshRaw }, { expiresIn: durations.refreshExpiresIn });

        await svc.storeRefreshToken(user.user_id, refreshRaw, durations.refreshExpiresAt);

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

        // Verify JWT signature first. NOTE: request.refreshVerify() (the
        // request-decorator form) only ever looks for a token in the
        // Authorization header or a cookie — it has no "token" option, so
        // passing one here was silently ignored and this ALWAYS threw.
        // fastify.jwt.refresh.verify(token) is the correct way to verify an
        // explicit token string pulled from the request body.
        let decoded;
        try {
            decoded = await fastify.jwt.refresh.verify(refreshToken);
        } catch {
            return reply.code(401).send({ error: 'Unauthorized', message: 'Invalid refresh token' });
        }

        // Atomically verify-and-revoke in one statement — if this returns
        // null, either the token never existed, was already rotated by a
        // concurrent request, or genuinely expired. Any of those is a clean
        // 401, not a race artifact.
        const stored = await svc.rotateRefreshToken(decoded.jti);
        if (!stored) {
            return reply.code(401).send({ error: 'Unauthorized', message: 'Refresh token revoked or expired' });
        }

        const payload = {
            user_id: stored.user_id,
            username: stored.username,
            role_codes: stored.role_codes || [],
        };

        const durations = await svc.computeSessionDurations(stored.user_id);

        const accessToken = await reply.accessSign(payload, { expiresIn: durations.accessExpiresIn });
        const refreshRaw = svc.generateRefreshTokenString();
        const newRefreshToken = await reply.refreshSign({ ...payload, jti: refreshRaw }, { expiresIn: durations.refreshExpiresIn });
        await svc.storeRefreshToken(stored.user_id, refreshRaw, durations.refreshExpiresAt);

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
            const decoded = await fastify.jwt.refresh.verify(refreshToken);
            if (decoded?.jti) {
                await svc.revokeRefreshToken(decoded.jti);
            }
        } catch {
            // Ignore invalid tokens on logout — just ack
        }
        return reply.code(200).send({ ok: true });
    });
};
