'use strict';

const { query } = require('../../../db/pool');
const { attachMediaUrls } = require('./mediaService');

module.exports = async function boardsRoutes(fastify) {
    const auth = { preHandler: [fastify.authenticate] };

    fastify.get('/', auth, async (request, reply) => {
        const { rows } = await query(
            `SELECT * FROM clinicqueue.display_boards ORDER BY board_name`,
            []
        );
        return reply.send({ data: rows.map(attachMediaUrls) });
    });

    fastify.post('/', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                required: ['board_code', 'board_name'],
                properties: {
                    board_code: { type: 'string' },
                    board_name: { type: 'string' },
                    description: { type: 'string' },
                    sound_enabled: { type: 'boolean' },
                    show_waiting_count: { type: 'boolean' },
                    max_in_service_rows: { type: 'integer' },
                    voice_speed: { type: 'number' },
                    language: { type: 'string' },
                    ding_sound: { type: 'string' },
                },
            },
        },
    }, async (request, reply) => {
        const { board_code, board_name, description, sound_enabled, show_waiting_count, max_in_service_rows, voice_speed, language, ding_sound } = request.body;
        const { rows } = await query(
            `INSERT INTO clinicqueue.display_boards (board_code, board_name, description, sound_enabled, show_waiting_count, max_in_service_rows, voice_speed, language, ding_sound)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING *`,
            [board_code.toUpperCase(), board_name, description || null,
            sound_enabled ?? true, show_waiting_count ?? true, max_in_service_rows ?? 10, voice_speed ?? 1.0, language || 'es', ding_sound || 'gentle']
        );
        return reply.code(201).send({ data: rows[0] });
    });

    fastify.put('/:id', {
        ...auth,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: {
                type: 'object',
                properties: {
                    board_name: { type: 'string' },
                    description: { type: 'string' },
                    sound_enabled: { type: 'boolean' },
                    show_waiting_count: { type: 'boolean' },
                    max_in_service_rows: { type: 'integer' },
                    voice_speed: { type: 'number' },
                    language: { type: 'string' },
                    ding_sound: { type: 'string' },
                },
            },
        },
    }, async (request, reply) => {
        const { id } = request.params;
        const { board_name, description, sound_enabled, show_waiting_count, max_in_service_rows, voice_speed, language, ding_sound } = request.body;
        const { rows } = await query(
            `UPDATE clinicqueue.display_boards
       SET board_name         = COALESCE($2, board_name),
           description        = COALESCE($3, description),
           sound_enabled      = COALESCE($4, sound_enabled),
           show_waiting_count = COALESCE($5, show_waiting_count),
           max_in_service_rows= COALESCE($6, max_in_service_rows),
           voice_speed        = COALESCE($7, voice_speed),
           language           = COALESCE($8, language),
           ding_sound         = COALESCE($9, ding_sound),
           updated_at         = now()
       WHERE board_id = $1
       RETURNING *`,
            [id, board_name, description, sound_enabled, show_waiting_count, max_in_service_rows, voice_speed, language, ding_sound]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Board not found' });
        return reply.send({ data: rows[0] });
    });

    fastify.patch('/:id/status', {
        ...auth,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: { type: 'object', required: ['is_active'], properties: { is_active: { type: 'boolean' } } },
        },
    }, async (request, reply) => {
        const { id } = request.params;
        const { rows } = await query(
            `UPDATE clinicqueue.display_boards SET is_active = $2, updated_at = now() WHERE board_id = $1 RETURNING *`,
            [id, request.body.is_active]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Board not found' });
        return reply.send({ data: rows[0] });
    });
};
