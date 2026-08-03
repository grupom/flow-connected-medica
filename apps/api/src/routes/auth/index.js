'use strict';

const { loginSchema, refreshSchema, logoutSchema } = require('./schemas');
const svc = require('./service');
const env = require('../../config/env');

// Shared cookie attributes for the two session cookies. `path` differs per
// cookie (see setSessionCookies) — the refresh cookie is scoped narrowly to
// /api/auth since only /refresh and /logout ever need to read it, shrinking
// the exposure of a token that can live up to 100 years for kiosk accounts.
function cookieOpts(path, expires) {
    return { httpOnly: true, sameSite: 'lax', secure: env.COOKIE_SECURE, path, expires };
}

function setSessionCookies(reply, accessToken, refreshToken, durations) {
    reply
        .setCookie('cq_access_token', accessToken, cookieOpts('/', durations.accessExpiresAt))
        .setCookie('cq_refresh_token', refreshToken, cookieOpts('/api/auth', durations.refreshExpiresAt));
}

// clearCookie defaults to path:'/' if not given explicitly — since
// cq_refresh_token was set at path:'/api/auth', clearing it without matching
// that path would create a *separate* cookie at '/' instead of removing the
// original, leaving it to linger in the browser. Both paths below must match
// what setSessionCookies used.
function clearSessionCookies(reply) {
    reply
        .clearCookie('cq_access_token', { path: '/', sameSite: 'lax', secure: env.COOKIE_SECURE })
        .clearCookie('cq_refresh_token', { path: '/api/auth', sameSite: 'lax', secure: env.COOKIE_SECURE });
}

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

        setSessionCookies(reply, accessToken, refreshToken, durations);

        return reply.code(200).send({
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
    // Now that the refresh JWT registration has a `cookie` fallback (see
    // plugins/jwt.js), the decorator form works correctly here — the earlier
    // manual fastify.jwt.refresh.verify(refreshToken) workaround was only
    // needed because there was no cookie/header for it to read.
    fastify.post('/refresh', { ...refreshSchema, preHandler: [fastify.authenticateRefresh] }, async (request, reply) => {
        const { jti } = request.user;

        // Atomically verify-and-revoke in one statement — if this returns
        // null, either the token never existed, was already rotated by a
        // concurrent request, or genuinely expired. Any of those is a clean
        // 401, not a race artifact.
        const stored = await svc.rotateRefreshToken(jti);
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

        setSessionCookies(reply, accessToken, newRefreshToken, durations);

        return reply.code(200).send({
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
    // Deliberately NOT using the authenticateRefresh preHandler here: logout
    // must stay a clean, always-{ok:true} no-op even with a missing/expired/
    // invalid refresh cookie (e.g. a second logout click, or a stale tab) —
    // a preHandler would 401 that case instead of just clearing cookies.
    fastify.post('/logout', logoutSchema, async (request, reply) => {
        try {
            await request.refreshVerify();
            if (request.user?.jti) {
                await svc.revokeRefreshToken(request.user.jti);
            }
        } catch {
            // Ignore invalid/missing/expired refresh cookie — always ack
        }
        clearSessionCookies(reply);
        return reply.code(200).send({ ok: true });
    });
};
