'use strict';

const { query } = require('../../../db/pool');

module.exports = async function modulesRoutes(fastify) {
    const auth = { preHandler: [fastify.authenticate] };

    fastify.get('/', auth, async (request, reply) => {
        const { rows } = await query(
            `SELECT * FROM clinicqueue.modules ORDER BY prefix, display_order, module_name`,
            []
        );
        return reply.send({ data: rows });
    });

    fastify.post('/', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                required: ['module_name', 'prefix'],
                properties: {
                    module_code:   { type: 'string' },
                    module_name:   { type: 'string' },
                    prefix:        { type: 'string' },
                    display_order: { type: 'integer' },
                },
            },
        },
    }, async (request, reply) => {
        const { module_name, prefix, display_order } = request.body;
        const cleanPrefix = prefix.trim().toUpperCase();

        // Auto-generate module_code as PREFIX + 2-digit counter if not supplied
        let { module_code } = request.body;
        if (!module_code) {
            // Get next counter for this prefix
            const { rows: cnt } = await query(
                `SELECT COUNT(*) AS total FROM clinicqueue.modules WHERE prefix = $1`,
                [cleanPrefix]
            );
            const nextNum = (parseInt(cnt[0].total, 10) + 1).toString().padStart(2, '0');
            module_code = cleanPrefix + nextNum;
        }

        const { rows } = await query(
            `INSERT INTO clinicqueue.modules (module_code, module_name, prefix, display_order)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
            [module_code.toUpperCase(), module_name, cleanPrefix, display_order || 1]
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
                    module_name:   { type: 'string' },
                    prefix:        { type: 'string' },
                    display_order: { type: 'integer' },
                },
            },
        },
    }, async (request, reply) => {
        const { id } = request.params;
        const { module_name, prefix, display_order } = request.body;
        const { rows } = await query(
            `UPDATE clinicqueue.modules
       SET module_name   = COALESCE($2, module_name),
           prefix        = COALESCE($3, prefix),
           display_order = COALESCE($4, display_order),
           updated_at    = now()
       WHERE module_id = $1
       RETURNING *`,
            [id, module_name || null, prefix ? prefix.trim().toUpperCase() : null, display_order || null]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Module not found' });
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
            `UPDATE clinicqueue.modules SET is_active = $2, updated_at = now() WHERE module_id = $1 RETURNING *`,
            [id, request.body.is_active]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Module not found' });
        return reply.send({ data: rows[0] });
    });
};
