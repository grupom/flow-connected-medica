'use strict';

const bcrypt = require('bcrypt');
const { query, transaction } = require('../../db/pool');
const crypto = require('crypto');
const env = require('../../config/env');

const KIOSK_ACCESS_EXPIRY = '24h';
const KIOSK_REFRESH_EXPIRY = '100y'; // "forever" without a schema change — see expires_at comparison below

/**
 * Parses the small set of expiry-string formats actually used in this
 * codebase ("15m", "24h", "7d", "100y") into milliseconds, so cookie
 * `expires` dates can track the same durations passed to jwt sign().
 */
function parseExpiryToMs(expiry) {
    const match = /^(\d+)([smhdy])$/.exec(expiry);
    if (!match) throw new Error(`Unsupported expiry format: ${expiry}`);
    const value = Number(match[1]);
    const unitMs = { s: 1000, m: 60000, h: 3600000, d: 86400000, y: 31536000000 }[match[2]];
    return value * unitMs;
}

/**
 * Lookup user by username or email from the login view.
 */
async function findUserForLogin(login) {
    const sql = `
    SELECT user_id, username, display_name, email, phone, is_active, password_hash, role_codes
    FROM clinicqueue.v_users_login
    WHERE (username = $1 OR email = $1)
    LIMIT 1
  `;
    const { rows } = await query(sql, [login.trim().toLowerCase()]);
    return rows[0] || null;
}

/**
 * Compare plain password to stored hash.
 */
async function verifyPassword(plain, hash) {
    return bcrypt.compare(plain, hash);
}

/**
 * Hash a plain password.
 */
async function hashPassword(plain) {
    return bcrypt.hash(plain, 12);
}

/**
 * Store a refresh token in the DB.
 */
async function storeRefreshToken(userId, token, expiresAt) {
    const sql = `
    INSERT INTO clinicqueue.refresh_tokens (user_id, token, expires_at)
    VALUES ($1, $2, $3)
  `;
    await query(sql, [userId, token, expiresAt]);
}

/**
 * Revoke a refresh token by token string.
 */
async function revokeRefreshToken(token) {
    const sql = `
    UPDATE clinicqueue.refresh_tokens
    SET revoked = true, revoked_at = now()
    WHERE token = $1
  `;
    await query(sql, [token]);
}

/**
 * Atomically verify-and-revoke a refresh token, returning the associated
 * user row only if this call was the one that revoked it. The verify
 * (SELECT) and revoke (UPDATE) happen in a single statement so two
 * concurrent requests presenting the same token can never both "win" —
 * exactly one UPDATE matches `revoked = false`, the other gets 0 rows back.
 * Used by /refresh instead of getStoredRefreshToken+revokeRefreshToken,
 * which had a check-then-act race between the SELECT and the UPDATE.
 */
async function rotateRefreshToken(token) {
    return transaction(async (client) => {
        const { rows } = await client.query(
            `UPDATE clinicqueue.refresh_tokens rt
             SET revoked = true, revoked_at = now()
             FROM clinicqueue.v_users_login u
             WHERE rt.token = $1
               AND rt.revoked = false
               AND rt.expires_at > now()
               AND u.user_id = rt.user_id
             RETURNING rt.user_id, u.username, u.display_name, u.email, u.phone, u.is_active, u.role_codes`,
            [token]
        );
        return rows[0] || null;
    });
}

/**
 * Check whether a user is bound to an active kiosk. Kiosks aren't a
 * role_code — they're a plain user account mapped via clinicqueue.kiosks —
 * same lookup as kiosk/service.js's getKioskSession().
 */
async function isKioskUser(userId) {
    const { rows } = await query(
        `SELECT 1 FROM clinicqueue.kiosks WHERE user_id = $1 AND is_active = true LIMIT 1`,
        [userId]
    );
    return rows.length > 0;
}

/**
 * Compute access/refresh token durations for a user, driven by the
 * admin-configurable session_duration_hours_staff / session_kiosk_no_expiry
 * settings (clinicqueue.system_settings). Falls back to sane defaults if
 * those rows don't exist yet (e.g. first boot, before Settings was saved).
 *
 * Kiosk refresh tokens use a far-future timestamp rather than a NULL/
 * "never" column so the existing `expires_at > now()` check in
 * rotateRefreshToken keeps working unchanged.
 */
async function computeSessionDurations(userId) {
    const [kiosk, { rows }] = await Promise.all([
        isKioskUser(userId),
        query(
            `SELECT key, value FROM clinicqueue.system_settings
             WHERE key IN ('session_duration_hours_staff', 'session_kiosk_no_expiry')`
        ),
    ]);
    const settings = Object.fromEntries(rows.map((r) => [r.key, r.value]));
    const staffHours = typeof settings.session_duration_hours_staff === 'number'
        ? settings.session_duration_hours_staff
        : 12;
    const kioskNoExpiry = typeof settings.session_kiosk_no_expiry === 'boolean'
        ? settings.session_kiosk_no_expiry
        : true;

    if (kiosk && kioskNoExpiry) {
        return {
            accessExpiresIn: KIOSK_ACCESS_EXPIRY,
            accessExpiresAt: new Date(Date.now() + parseExpiryToMs(KIOSK_ACCESS_EXPIRY)),
            refreshExpiresIn: KIOSK_REFRESH_EXPIRY,
            refreshExpiresAt: new Date(Date.now() + 100 * 365 * 24 * 60 * 60 * 1000),
        };
    }

    return {
        accessExpiresIn: env.JWT_ACCESS_EXPIRY,
        accessExpiresAt: new Date(Date.now() + parseExpiryToMs(env.JWT_ACCESS_EXPIRY)),
        refreshExpiresIn: `${staffHours}h`,
        refreshExpiresAt: new Date(Date.now() + staffHours * 60 * 60 * 1000),
    };
}

/**
 * Call the DB function to update last_login_at.
 */
async function touchLastLogin(userId) {
    try {
        await query('SELECT clinicqueue.touch_last_login($1)', [userId]);
    } catch {
        // fallback: direct update if function doesn't exist
        await query(
            'UPDATE clinicqueue.users SET last_login_at = now(), updated_at = now() WHERE user_id = $1',
            [userId]
        );
    }
}

/**
 * Generate a cryptographically random opaque refresh token string.
 */
function generateRefreshTokenString() {
    return crypto.randomBytes(64).toString('hex');
}

module.exports = {
    findUserForLogin,
    verifyPassword,
    hashPassword,
    storeRefreshToken,
    rotateRefreshToken,
    revokeRefreshToken,
    isKioskUser,
    computeSessionDurations,
    touchLastLogin,
    generateRefreshTokenString,
};
