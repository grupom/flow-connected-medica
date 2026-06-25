'use strict';

const { query } = require('../../../db/pool');

// Tables wiped on factory-reset (order respects FK dependencies).
// Roles and users are intentionally excluded.
const RESET_TABLES = [
    'clinicqueue.ticket_events',
    'clinicqueue.ticket_transfers',
    'clinicqueue.queue_counters',
    'clinicqueue.station_users',
    'clinicqueue.kiosk_queues',
    'clinicqueue.board_stations',
    'clinicqueue.tickets',
    'clinicqueue.kiosks',
    'clinicqueue.daily_close_runs',
    'clinicqueue.display_boards',
    'clinicqueue.stations',
    'clinicqueue.modules',
    'clinicqueue.queue_settings',
];

module.exports = async function settingsRoutes(fastify) {
    const auth      = { preHandler: [fastify.authenticate] };
    const adminOnly = {
        preHandler: [
            fastify.authenticate,
            async (request, reply) => {
                const roles = request.user?.role_codes ?? [];
                if (!roles.includes('ADMIN')) {
                    return reply.code(403).send({ error: 'Forbidden', message: 'Se requiere rol ADMIN' });
                }
            },
        ],
    };

    // GET /api/admin/settings
    // Returns all system settings as a flat key→value object
    fastify.get('/', auth, async (_request, reply) => {
        const { rows } = await query(
            `SELECT key, value FROM clinicqueue.system_settings ORDER BY key`
        );
        const data = Object.fromEntries(rows.map(r => [r.key, r.value]));
        return reply.send({ data });
    });

    // PATCH /api/admin/settings
    // Upserts one or more settings. Body: { multi_language: true, ... }
    fastify.patch('/', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                minProperties: 1,
                additionalProperties: { type: ['boolean', 'string', 'number', 'object', 'array', 'null'] },
            },
        },
    }, async (request, reply) => {
        const entries = Object.entries(request.body);

        for (const [key, value] of entries) {
            await query(
                `INSERT INTO clinicqueue.system_settings (key, value, updated_at)
                 VALUES ($1, $2::jsonb, NOW())
                 ON CONFLICT (key) DO UPDATE
                    SET value = EXCLUDED.value,
                        updated_at = EXCLUDED.updated_at`,
                [key, JSON.stringify(value)]
            );
        }

        const { rows } = await query(
            `SELECT key, value FROM clinicqueue.system_settings ORDER BY key`
        );
        const data = Object.fromEntries(rows.map(r => [r.key, r.value]));
        return reply.send({ data });
    });

    // POST /api/admin/settings/factory-reset
    // Wipes all operational data (tickets, stations, boards, kiosks, etc.)
    // and resets sequences. Roles and users are preserved.
    fastify.post('/factory-reset', adminOnly, async (_request, reply) => {
        const tableList = RESET_TABLES.join(', ');
        await query(`TRUNCATE ${tableList} RESTART IDENTITY CASCADE`);
        return reply.send({
            ok: true,
            message: 'Sistema reiniciado. Todos los datos operativos han sido eliminados.',
            cleared: RESET_TABLES.length,
        });
    });
};
