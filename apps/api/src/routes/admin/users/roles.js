'use strict';

const { query } = require('../../../db/pool');

module.exports = async function userRolesRoutes(fastify) {
    const auth = { preHandler: [fastify.authenticate] };

    // POST /api/admin/users/:id/roles — assign a role to a user
    fastify.post('/:id/roles', {
        ...auth,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: {
                type: 'object',
                required: ['role_id'],
                properties: { role_id: { type: 'integer' } },
            },
        },
    }, async (request, reply) => {
        const { id } = request.params;
        const { role_id } = request.body;
        const assigned_by = request.user.user_id;

        const { rows } = await query(
            `INSERT INTO clinicqueue.user_roles (user_id, role_id, assigned_by)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, role_id) DO NOTHING
       RETURNING user_id, role_id, assigned_at`,
            [id, role_id, assigned_by]
        );
        return reply.code(201).send({ data: rows[0] || { user_id: id, role_id, note: 'already assigned' } });
    });

    // DELETE /api/admin/users/:id/roles/:roleId — remove role from user
    fastify.delete('/:id/roles/:roleId', {
        ...auth,
        schema: {
            params: {
                type: 'object',
                properties: {
                    id: { type: 'integer' },
                    roleId: { type: 'integer' },
                },
            },
        },
    }, async (request, reply) => {
        const { id, roleId } = request.params;
        await query(
            `DELETE FROM clinicqueue.user_roles WHERE user_id = $1 AND role_id = $2`,
            [id, roleId]
        );
        return reply.send({ ok: true });
    });
};
