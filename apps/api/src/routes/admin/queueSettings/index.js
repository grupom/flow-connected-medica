'use strict';

const { query } = require('../../../db/pool');

module.exports = async function queueSettingsRoutes(fastify) {
    const auth = { preHandler: [fastify.authenticate] };

    // GET /api/admin/queue-settings
    // ?include_archived=true  → returns all (active + archived)
    fastify.get('/', auth, async (request, reply) => {
        const includeArchived = request.query.include_archived === 'true';
        const { rows } = await query(
            `SELECT * FROM clinicqueue.queue_settings
             ${includeArchived ? '' : 'WHERE archived = false'}
             ORDER BY archived, prefix`
        );
        return reply.send({ data: rows });
    });

    // POST /api/admin/queue-settings
    fastify.post('/', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                required: ['prefix'],
                properties: {
                    prefix:          { type: 'string' },
                    service_name:    { type: 'string' },
                    icon:            { type: 'string' },
                    mode:            { type: 'string', enum: ['DAILY_RESET', 'GLOBAL'] },
                    min_number:      { type: 'integer' },
                    max_number:      { type: 'integer' },
                    max_active:      { type: 'integer', nullable: true },
                    allow_walkins:   { type: 'boolean' },
                    is_priority_for: { type: 'string',  nullable: true },
                },
            },
        },
    }, async (request, reply) => {
        const {
            prefix,
            service_name,
            icon,
            mode            = 'DAILY_RESET',
            min_number      = 1,
            max_number      = 99,
            max_active      = null,
            allow_walkins   = true,
            is_priority_for = null,
        } = request.body;

        const cleanPrefix    = prefix.trim().toUpperCase();
        const cleanParent    = is_priority_for ? is_priority_for.trim().toUpperCase() : null;
        // Priority prefixes must not allow kiosk walk-ins
        const effectiveWalkins = cleanParent ? false : allow_walkins;

        try {
            const { rows } = await query(
                `INSERT INTO clinicqueue.queue_settings
                 (prefix, service_name, icon, mode, min_number, max_number, max_active, allow_walkins, is_priority_for)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                 RETURNING *`,
                [cleanPrefix, service_name, icon, mode, min_number, max_number, max_active, effectiveWalkins, cleanParent]
            );
            return reply.code(201).send({ data: rows[0] });
        } catch (e) {
            if (e.code === '23505') {
                return reply.code(400).send({ error: 'Bad Request', message: `Prefix '${cleanPrefix}' already exists.` });
            }
            throw e;
        }
    });

    // PUT /api/admin/queue-settings/:prefix
    fastify.put('/:prefix', {
        ...auth,
        schema: {
            params: { type: 'object', properties: { prefix: { type: 'string' } } },
            body: {
                type: 'object',
                properties: {
                    service_name:    { type: 'string' },
                    icon:            { type: 'string' },
                    mode:            { type: 'string', enum: ['DAILY_RESET', 'GLOBAL'] },
                    min_number:      { type: 'integer' },
                    max_number:      { type: 'integer' },
                    max_active:      { type: 'integer', nullable: true },
                    allow_walkins:   { type: 'boolean' },
                    is_priority_for: { type: 'string',  nullable: true },
                },
            },
        },
    }, async (request, reply) => {
        const p = request.params.prefix.trim().toUpperCase();
        const { service_name, icon, mode, min_number, max_number, max_active, allow_walkins, is_priority_for } = request.body;

        const cleanParent    = is_priority_for !== undefined
            ? (is_priority_for ? is_priority_for.trim().toUpperCase() : null)
            : undefined;
        // If switching to a priority prefix, force allow_walkins = false
        const effectiveWalkins = cleanParent !== undefined && cleanParent !== null
            ? false
            : allow_walkins;

        const { rows } = await query(
            `UPDATE clinicqueue.queue_settings
             SET service_name    = COALESCE($2, service_name),
                 icon            = COALESCE($3, icon),
                 mode            = COALESCE($4, mode),
                 min_number      = COALESCE($5, min_number),
                 max_number      = COALESCE($6, max_number),
                 max_active      = $7,
                 allow_walkins   = COALESCE($8, allow_walkins),
                 is_priority_for = $9,
                 updated_at      = now()
             WHERE prefix = $1
             RETURNING *`,
            [
                p,
                service_name,
                icon,
                mode,
                min_number,
                max_number,
                max_active !== undefined ? max_active : null,
                effectiveWalkins,
                cleanParent !== undefined ? cleanParent : null,
            ]
        );

        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Setting not found' });
        return reply.send({ data: rows[0] });
    });

    // PATCH /api/admin/queue-settings/:prefix/archive
    fastify.patch('/:prefix/archive', auth, async (request, reply) => {
        const p = request.params.prefix.trim().toUpperCase();
        const { rows } = await query(
            `UPDATE clinicqueue.queue_settings
             SET archived = true, updated_at = now()
             WHERE prefix = $1
             RETURNING *`,
            [p]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Setting not found' });
        return reply.send({ data: rows[0] });
    });

    // PATCH /api/admin/queue-settings/:prefix/restore
    fastify.patch('/:prefix/restore', auth, async (request, reply) => {
        const p = request.params.prefix.trim().toUpperCase();
        const { rows } = await query(
            `UPDATE clinicqueue.queue_settings
             SET archived = false, updated_at = now()
             WHERE prefix = $1
             RETURNING *`,
            [p]
        );
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Setting not found' });
        return reply.send({ data: rows[0] });
    });
};
