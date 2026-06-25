'use strict';

const { query } = require('../../../db/pool');

module.exports = async function rolesRoutes(fastify) {
    const auth = { preHandler: [fastify.authenticate] };

    // GET /api/admin/roles
    fastify.get('/', auth, async (request, reply) => {
        const { rows } = await query(
            `SELECT role_id, role_code, role_name, description, is_active, created_at, updated_at
       FROM clinicqueue.roles ORDER BY role_name`,
            []
        );
        return reply.send({ data: rows });
    });

    // POST /api/admin/roles
    fastify.post('/', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                required: ['role_code', 'role_name'],
                properties: {
                    role_code: { type: 'string' },
                    role_name: { type: 'string' },
                    description: { type: 'string' },
                },
            },
        },
    }, async (request, reply) => {
        const { role_code, role_name, description } = request.body;
        const { rows } = await query(
            `INSERT INTO clinicqueue.roles (role_code, role_name, description)
       VALUES ($1, $2, $3)
       RETURNING role_id, role_code, role_name, description, is_active, created_at`,
            [role_code.toUpperCase(), role_name, description || null]
        );
        return reply.code(201).send({ data: rows[0] });
    });

    // PUT /api/admin/roles/:id
    fastify.put('/:id', {
        ...auth,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: {
                type: 'object',
                properties: {
                    role_name: { type: 'string' },
                    description: { type: 'string' },
                },
            },
        },
    }, async (request, reply) => {
        const { id } = request.params;
        const { role_name, description } = request.body;
        const { rows } = await query(
            `UPDATE clinicqueue.roles
       SET role_name   = COALESCE($2, role_name),
           description = COALESCE($3, description),
           updated_at  = now()
       WHERE role_id = $1
       RETURNING role_id, role_code, role_name, description, is_active, updated_at`,
            [id, role_name, description]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Role not found' });
        return reply.send({ data: rows[0] });
    });

    // PATCH /api/admin/roles/:id/status
    fastify.patch('/:id/status', {
        ...auth,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: {
                type: 'object',
                required: ['is_active'],
                properties: { is_active: { type: 'boolean' } },
            },
        },
    }, async (request, reply) => {
        const { id } = request.params;
        const { rows } = await query(
            `UPDATE clinicqueue.roles SET is_active = $2, updated_at = now() WHERE role_id = $1
       RETURNING role_id, role_code, is_active`,
            [id, request.body.is_active]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Role not found' });
        return reply.send({ data: rows[0] });
    });
};
