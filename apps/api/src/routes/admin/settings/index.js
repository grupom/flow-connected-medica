'use strict';

const bcrypt = require('bcrypt');
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
    const auth = { preHandler: [fastify.authenticate] };

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
    // ADMIN-only: this endpoint can change security-relevant settings
    // (e.g. session_duration_hours_staff), not just cosmetic ones.
    fastify.patch('/', {
        ...fastify.adminOnly,
        schema: {
            body: {
                type: 'object',
                minProperties: 1,
                additionalProperties: { type: ['boolean', 'string', 'number', 'object', 'array', 'null'] },
                properties: {
                    session_duration_hours_staff: { type: 'integer', minimum: 8, maximum: 16 },
                    session_kiosk_no_expiry: { type: 'boolean' },
                    no_show_requeue_limit: { type: 'integer', minimum: 1, maximum: 20 },
                },
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
    // Requires the calling admin's own current password — a valid ADMIN
    // token alone (e.g. leaked/stolen) is not enough to trigger this
    // irreversible action. The frontend's "type RESET" prompt is a UX
    // safety net against fat-fingering, not a security boundary: it's a
    // client-side check readable in the bundled JS, so it can't be what
    // stops a stolen token from being enough.
    fastify.post('/factory-reset', {
        ...fastify.adminOnly,
        schema: {
            body: {
                type: 'object',
                required: ['password'],
                properties: { password: { type: 'string', minLength: 1 } },
            },
        },
    }, async (request, reply) => {
        const { rows } = await query(
            `SELECT password_hash FROM clinicqueue.users WHERE user_id = $1`,
            [request.user.user_id]
        );
        const passwordHash = rows[0]?.password_hash;
        const passOk = passwordHash && await bcrypt.compare(request.body.password, passwordHash);
        if (!passOk) {
            return reply.code(401).send({ error: 'Unauthorized', message: 'Contraseña incorrecta' });
        }

        const tableList = RESET_TABLES.join(', ');
        await query(`TRUNCATE ${tableList} RESTART IDENTITY CASCADE`);
        return reply.send({
            ok: true,
            message: 'Sistema reiniciado. Todos los datos operativos han sido eliminados.',
            cleared: RESET_TABLES.length,
        });
    });
};
