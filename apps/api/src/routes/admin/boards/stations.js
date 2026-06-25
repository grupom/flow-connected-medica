'use strict';

const { query } = require('../../../db/pool');

module.exports = async function boardStationsRoutes(fastify) {
    const auth = { preHandler: [fastify.authenticate] };

    // GET /api/admin/boards/:boardId/stations
    fastify.get('/:boardId/stations', {
        ...auth,
        schema: { params: { type: 'object', properties: { boardId: { type: 'integer' } } } },
    }, async (request, reply) => {
        const { rows } = await query(
            `SELECT bs.*, s.station_code, s.station_name
       FROM clinicqueue.board_stations bs
       JOIN clinicqueue.stations s ON s.station_id = bs.station_id
       WHERE bs.board_id = $1
       ORDER BY bs.display_order`,
            [request.params.boardId]
        );
        return reply.send({ data: rows });
    });

    // POST /api/admin/boards/:boardId/stations
    fastify.post('/:boardId/stations', {
        ...auth,
        schema: {
            params: { type: 'object', properties: { boardId: { type: 'integer' } } },
            body: {
                type: 'object',
                required: ['station_id'],
                properties: {
                    station_id: { type: 'integer' },
                    display_order: { type: 'integer' },
                    is_enabled: { type: 'boolean' },
                },
            },
        },
    }, async (request, reply) => {
        const { boardId } = request.params;
        const { station_id, display_order, is_enabled } = request.body;
        const { rows } = await query(
            `INSERT INTO clinicqueue.board_stations (board_id, station_id, display_order, is_enabled)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (board_id, station_id) DO UPDATE
         SET display_order = EXCLUDED.display_order,
             is_enabled    = EXCLUDED.is_enabled
       RETURNING *`,
            [boardId, station_id, display_order ?? 0, is_enabled ?? true]
        );
        return reply.code(201).send({ data: rows[0] });
    });

    // PUT /api/admin/boards/:boardId/stations/:stationId
    fastify.put('/:boardId/stations/:stationId', {
        ...auth,
        schema: {
            params: {
                type: 'object',
                properties: { boardId: { type: 'integer' }, stationId: { type: 'integer' } },
            },
            body: {
                type: 'object',
                properties: {
                    display_order: { type: 'integer' },
                    is_enabled: { type: 'boolean' },
                },
            },
        },
    }, async (request, reply) => {
        const { boardId, stationId } = request.params;
        const { display_order, is_enabled } = request.body;
        const { rows } = await query(
            `UPDATE clinicqueue.board_stations
       SET display_order = COALESCE($3, display_order),
           is_enabled    = COALESCE($4, is_enabled)
       WHERE board_id = $1 AND station_id = $2
       RETURNING *`,
            [boardId, stationId, display_order, is_enabled]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Board station not found' });
        return reply.send({ data: rows[0] });
    });

    // DELETE /api/admin/boards/:boardId/stations/:stationId
    fastify.delete('/:boardId/stations/:stationId', {
        ...auth,
        schema: {
            params: {
                type: 'object',
                properties: { boardId: { type: 'integer' }, stationId: { type: 'integer' } },
            },
        },
    }, async (request, reply) => {
        const { boardId, stationId } = request.params;
        await query(
            `DELETE FROM clinicqueue.board_stations WHERE board_id = $1 AND station_id = $2`,
            [boardId, stationId]
        );
        return reply.send({ ok: true });
    });
};
