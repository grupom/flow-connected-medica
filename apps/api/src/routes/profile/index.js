'use strict';

const bcrypt = require('bcrypt');
const { query } = require('../../db/pool');

module.exports = async function profileRoutes(fastify) {
    const auth = { preHandler: [fastify.authenticate] };

    // GET /api/profile — get current user profile
    fastify.get('/', auth, async (request, reply) => {
        const userId = request.user.user_id;
        const { rows } = await query(
            `SELECT u.user_id, u.username, u.display_name, u.email, u.phone,
                    u.created_at, u.last_login_at
             FROM clinicqueue.users u
             WHERE u.user_id = $1`,
            [userId]
        );
        if (!rows.length) {
            return reply.code(404).send({ error: 'User not found' });
        }

        // Get roles
        const { rows: roleRows } = await query(
            `SELECT r.role_code, r.role_name
             FROM clinicqueue.user_roles ur
             JOIN clinicqueue.roles r ON r.role_id = ur.role_id
             WHERE ur.user_id = $1 AND r.is_active = true`,
            [userId]
        );

        return reply.send({
            data: {
                ...rows[0],
                roles: roleRows,
            }
        });
    });

    // PUT /api/profile — update profile info
    fastify.put('/', auth, async (request, reply) => {
        const userId = request.user.user_id;
        const { display_name, email, phone } = request.body;

        const { rows } = await query(
            `UPDATE clinicqueue.users
             SET display_name = COALESCE($2, display_name),
                 email = COALESCE($3, email),
                 phone = COALESCE($4, phone),
                 updated_at = now()
             WHERE user_id = $1
             RETURNING user_id, username, display_name, email, phone`,
            [userId, display_name, email, phone]
        );

        if (!rows.length) {
            return reply.code(404).send({ error: 'User not found' });
        }
        return reply.send({ data: rows[0] });
    });

    // PUT /api/profile/password — change password
    fastify.put('/password', auth, async (request, reply) => {
        const userId = request.user.user_id;
        const { current_password, new_password } = request.body;

        if (!current_password || !new_password) {
            return reply.code(400).send({ error: 'Both current and new passwords required' });
        }
        if (new_password.length < 6) {
            return reply.code(400).send({ error: 'New password must be at least 6 characters' });
        }

        // Verify current password
        const { rows } = await query(
            `SELECT password_hash FROM clinicqueue.users WHERE user_id = $1`,
            [userId]
        );
        if (!rows.length) {
            return reply.code(404).send({ error: 'User not found' });
        }

        const valid = await bcrypt.compare(current_password, rows[0].password_hash);
        if (!valid) {
            return reply.code(401).send({ error: 'Current password is incorrect' });
        }

        const hash = await bcrypt.hash(new_password, 12);
        await query(
            `UPDATE clinicqueue.users SET password_hash = $2, updated_at = now() WHERE user_id = $1`,
            [userId, hash]
        );

        return reply.send({ ok: true, message: 'Password updated successfully' });
    });
};
