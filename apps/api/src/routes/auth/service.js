'use strict';

const bcrypt = require('bcrypt');
const { query } = require('../../db/pool');
const crypto = require('crypto');

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
 * Verify a stored refresh token is valid (not revoked, not expired).
 */
async function getStoredRefreshToken(token) {
    const sql = `
    SELECT rt.token_id, rt.user_id, rt.expires_at, rt.revoked,
           u.username, u.display_name, u.email, u.phone, u.is_active, u.role_codes
    FROM clinicqueue.refresh_tokens rt
    JOIN clinicqueue.v_users_login u ON u.user_id = rt.user_id
    WHERE rt.token = $1
      AND rt.revoked = false
      AND rt.expires_at > now()
    LIMIT 1
  `;
    const { rows } = await query(sql, [token]);
    return rows[0] || null;
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
    getStoredRefreshToken,
    revokeRefreshToken,
    touchLastLogin,
    generateRefreshTokenString,
};
