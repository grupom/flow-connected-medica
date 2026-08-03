'use strict';

const { query } = require('../../../db/pool');

module.exports = async function stationsRoutes(fastify) {
    fastify.get('/', fastify.adminOnly, async (request, reply) => {
        const { rows } = await query(
            `SELECT s.*, m.module_name, m.module_code
             FROM clinicqueue.stations s
             LEFT JOIN clinicqueue.modules m ON s.module_id = m.module_id
             ORDER BY s.station_name`,
            []
        );
        return reply.send({ data: rows });
    });

    fastify.post('/', {
        ...fastify.adminOnly,
        schema: {
            body: {
                type: 'object',
                required: ['station_name', 'prefix'],
                properties: {
                    station_code: { type: 'string' },
                    station_name: { type: 'string' },
                    prefix:       { type: 'string' },
                    module_id:    { type: 'integer' },
                },
            },
        },
    }, async (request, reply) => {
        const { station_name, prefix, module_id } = request.body;
        // Auto-generate station_code if not supplied
        let { station_code } = request.body;
        if (!station_code) {
            station_code = (prefix + '_' + station_name)
                .toUpperCase()
                .replace(/[^A-Z0-9_]/g, '_')
                .slice(0, 30);
        }
        const { rows } = await query(
            `INSERT INTO clinicqueue.stations (station_code, station_name, prefix, module_id)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
            [station_code.toUpperCase(), station_name, prefix.toUpperCase(), module_id || null]
        );
        return reply.code(201).send({ data: rows[0] });
    });

    fastify.put('/:id', {
        ...fastify.adminOnly,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: {
                type: 'object',
                properties: {
                    station_name: { type: 'string' },
                    prefix:       { type: 'string' },
                    module_id:    { type: 'integer' },
                },
            },
        },
    }, async (request, reply) => {
        const { id } = request.params;
        const { station_name, prefix, module_id } = request.body;
        const { rows } = await query(
            `UPDATE clinicqueue.stations
       SET station_name = COALESCE($2, station_name),
           prefix       = COALESCE($3, prefix),
           module_id    = COALESCE($4, module_id),
           updated_at   = now()
       WHERE station_id = $1
       RETURNING *`,
            [id, station_name || null, prefix ? prefix.toUpperCase() : null, module_id || null]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Station not found' });
        return reply.send({ data: rows[0] });
    });

    fastify.patch('/:id/status', {
        ...fastify.adminOnly,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: { type: 'object', required: ['is_active'], properties: { is_active: { type: 'boolean' } } },
        },
    }, async (request, reply) => {
        const { id } = request.params;
        const { rows } = await query(
            `UPDATE clinicqueue.stations SET is_active = $2, updated_at = now() WHERE station_id = $1 RETURNING *`,
            [id, request.body.is_active]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Station not found' });
        return reply.send({ data: rows[0] });
    });
};
