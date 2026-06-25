'use strict';

const { query } = require('../../../db/pool');
const bcrypt = require('bcrypt');

module.exports = async function usersRoutes(fastify) {
    const auth = { preHandler: [fastify.authenticate] };

    // GET /api/admin/users
    fastify.get('/', auth, async (request, reply) => {
        const { rows } = await query(
            `SELECT * FROM clinicqueue.v_users ORDER BY display_name`,
            []
        );
        return reply.send({ data: rows });
    });

    // POST /api/admin/users
    fastify.post('/', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                required: ['username', 'email', 'full_name', 'password'],
                properties: {
                    username: { type: 'string' },
                    email: { type: 'string', format: 'email' },
                    full_name: { type: 'string' },
                    phone: { type: 'string' },
                    password: { type: 'string', minLength: 6 },
                    role_id: { type: 'integer' }
                },
            },
        },
    }, async (request, reply) => {
        const { username, email, full_name, phone, password, role_id } = request.body;
        const password_hash = await bcrypt.hash(password, 12);

        // Enforce status_code logic natively, skip is_active
        const { rows } = await query(
            `INSERT INTO clinicqueue.users (username, email, display_name, phone, password_hash, status_code)
             VALUES ($1, $2, $3, $4, $5, 'ACTIVE')
             RETURNING user_id, username, email, display_name, phone, status_code, created_at`,
            [username.trim().toLowerCase(), email.trim().toLowerCase(), full_name, phone || null, password_hash]
        );
        
        const newUser = rows[0];
        if (role_id) {
            await query(`INSERT INTO clinicqueue.user_roles (user_id, role_id) VALUES ($1, $2)`, [newUser.user_id, role_id]);
        }

        return reply.code(201).send({ data: newUser });
    });

    // PUT /api/admin/users/:id
    fastify.put('/:id', {
        ...auth,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: {
                type: 'object',
                properties: {
                    full_name: { type: 'string' },
                    email: { type: 'string', format: 'email' },
                    phone: { type: 'string' },
                },
            },
        },
    }, async (request, reply) => {
        const { id } = request.params;
        const { full_name, email, phone } = request.body;

        const { rows } = await query(
            `UPDATE clinicqueue.users
             SET display_name = COALESCE($2, display_name),
                 email        = COALESCE($3, email),
                 phone        = COALESCE($4, phone),
                 updated_at   = now()
             WHERE user_id = $1
             RETURNING user_id, username, email, display_name, phone, status_code, updated_at`,
            [id, full_name, email, phone]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'User not found' });
        return reply.send({ data: rows[0] });
    });

    // PATCH /api/admin/users/:id/status
    fastify.patch('/:id/status', {
        ...auth,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: {
                type: 'object',
                required: ['status_code'],
                properties: { status_code: { type: 'string', enum: ['ACTIVE', 'INACTIVE', 'ARCHIVED'] } },
            },
        },
    }, async (request, reply) => {
        const { id } = request.params;
        const { status_code } = request.body;
        const { rows } = await query(
            `UPDATE clinicqueue.users SET status_code = $2, updated_at = now() WHERE user_id = $1
             RETURNING user_id, username, status_code`,
            [id, status_code]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'User not found' });
        return reply.send({ data: rows[0] });
    });

    // PATCH /api/admin/users/:id/password
    fastify.patch('/:id/password', {
        ...auth,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: {
                type: 'object',
                required: ['password'],
                properties: { password: { type: 'string', minLength: 6 } },
            },
        },
    }, async (request, reply) => {
        const { id } = request.params;
        const password_hash = await bcrypt.hash(request.body.password, 12);
        const { rows } = await query(
            `UPDATE clinicqueue.users SET password_hash = $2, updated_at = now() WHERE user_id = $1
       RETURNING user_id, username, updated_at`,
            [id, password_hash]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'User not found' });
        return reply.send({ ok: true, data: rows[0] });
    });
};
