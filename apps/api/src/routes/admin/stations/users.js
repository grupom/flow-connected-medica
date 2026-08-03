'use strict';

const { query } = require('../../../db/pool');

module.exports = async function stationUsersRoutes(fastify) {
    // GET /api/admin/stations/:stationId/users
    fastify.get('/:stationId/users', {
        ...fastify.adminOnly,
        schema: { params: { type: 'object', properties: { stationId: { type: 'integer' } } } },
    }, async (request, reply) => {
        const { stationId } = request.params;
        const { rows } = await query(
            `SELECT su.*, u.username, u.display_name
       FROM clinicqueue.station_users su
       JOIN clinicqueue.users u ON u.user_id = su.user_id
       WHERE su.station_id = $1
       ORDER BY u.display_name`,
            [stationId]
        );
        return reply.send({ data: rows });
    });

    // POST /api/admin/stations/:stationId/users
    fastify.post('/:stationId/users', {
        ...fastify.adminOnly,
        schema: {
            params: { type: 'object', properties: { stationId: { type: 'integer' } } },
            body: {
                type: 'object',
                required: ['user_id'],
                properties: {
                    user_id: { type: 'integer' },
                },
            },
        },
    }, async (request, reply) => {
        const { stationId } = request.params;
        const { user_id } = request.body;
        const { rows } = await query(
            `INSERT INTO clinicqueue.station_users (station_id, user_id)
             VALUES ($1, $2)
             ON CONFLICT (station_id, user_id) DO UPDATE
               SET is_enabled = true
             RETURNING *`,
            [stationId, user_id]
        );
        return reply.code(201).send({ data: rows[0] });
    });

    // PATCH /api/admin/stations/:stationId/users/:userId
    fastify.patch('/:stationId/users/:userId', {
        ...fastify.adminOnly,
        schema: {
            params: {
                type: 'object',
                properties: { stationId: { type: 'integer' }, userId: { type: 'integer' } },
            },
            body: {
                type: 'object',
                properties: {
                    is_enabled: { type: 'boolean' },
                },
            },
        },
    }, async (request, reply) => {
        const { stationId, userId } = request.params;
        const { is_enabled } = request.body;
        const { rows } = await query(
            `UPDATE clinicqueue.station_users
             SET is_enabled = COALESCE($3, is_enabled)
             WHERE station_id = $1 AND user_id = $2
             RETURNING *`,
            [stationId, userId, is_enabled]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Assignment not found' });
        return reply.send({ data: rows[0] });
    });

    // DELETE /api/admin/stations/:stationId/users/:userId
    fastify.delete('/:stationId/users/:userId', {
        ...fastify.adminOnly,
        schema: {
            params: {
                type: 'object',
                properties: { stationId: { type: 'integer' }, userId: { type: 'integer' } },
            },
        },
    }, async (request, reply) => {
        const { stationId, userId } = request.params;
        await query(
            `DELETE FROM clinicqueue.station_users WHERE station_id = $1 AND user_id = $2`,
            [stationId, userId]
        );
        return reply.send({ ok: true });
    });
};
