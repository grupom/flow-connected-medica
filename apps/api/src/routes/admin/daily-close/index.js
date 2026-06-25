'use strict';

const { query } = require('../../../db/pool');
const { previewSchema, runSchema } = require('./schema');

module.exports = async function dailyCloseRoutes(fastify) {
    const checkRole = async (request, reply) => {
        const userRoles = request.user?.role_codes || [];
        if (!userRoles.includes('ADMIN') && !userRoles.includes('SUPERVISOR')) {
            return reply.code(403).send({ error: 'Forbidden', message: 'Requires ADMIN or SUPERVISOR role' });
        }
    };

    const authOpts = {
        preHandler: [fastify.authenticate, checkRole]
    };

    fastify.post('/preview', {
        ...authOpts,
        schema: previewSchema
    }, async (request, reply) => {
        const { operational_date } = request.body;
        const userId = request.user.user_id;

        try {
            const { rows } = await query(
                `SELECT * FROM clinicqueue.close_daily_open_tickets($1::date, 'MANUAL', $2::bigint, true)`,
                [operational_date, userId]
            );
            return reply.send({ data: rows });
        } catch (e) {
            fastify.log.error(e);
            return reply.code(500).send({ error: 'Internal Server Error', message: e.message });
        }
    });

    fastify.post('/run', {
        ...authOpts,
        schema: runSchema
    }, async (request, reply) => {
        const { operational_date } = request.body;
        const userId = request.user.user_id;

        try {
            const { rows } = await query(
                `SELECT * FROM clinicqueue.close_daily_open_tickets($1::date, 'MANUAL', $2::bigint, false)`,
                [operational_date, userId]
            );
            return reply.send({ data: rows });
        } catch (e) {
            fastify.log.error(e);
            return reply.code(500).send({ error: 'Internal Server Error', message: e.message });
        }
    });

    fastify.get('/runs', {
        ...authOpts
    }, async (request, reply) => {
        try {
            // Retrieve history of daily close runs
            const { rows } = await query(
                `SELECT r.run_id, r.run_mode, r.operational_date, r.started_at, r.finished_at, r.tickets_closed,
                        u.display_name as executed_by_name
                 FROM clinicqueue.daily_close_runs r
                 LEFT JOIN clinicqueue.users u ON r.executed_by = u.user_id
                 ORDER BY r.started_at DESC
                 LIMIT 100`
            );
            return reply.send({ data: rows });
        } catch (e) {
            fastify.log.error(e);
            return reply.code(500).send({ error: 'Internal Server Error', message: e.message });
        }
    });

    fastify.get('/runs/:runId', {
        ...authOpts,
        schema: {
            params: {
                type: 'object',
                properties: { runId: { type: 'integer' } }
            }
        }
    }, async (request, reply) => {
        const { runId } = request.params;
        try {
            // Reconstruct the payload of closed tickets from the ticket_events history
            const { rows } = await query(
                `SELECT t.ticket_id, t.code, t.prefix, t.tck_number, 
                        te.from_status as old_status, te.to_status as new_status,
                        t.ticket_date, te.event_at as closed_at
                 FROM clinicqueue.ticket_events te
                 JOIN clinicqueue.tickets t ON te.ticket_id = t.ticket_id
                 WHERE te.event_type = 'AUTO_CLOSED'
                   AND (te.details->>'run_id')::bigint = $1
                 ORDER BY t.ticket_date DESC, t.prefix, t.tck_number ASC`,
                [runId]
            );
            return reply.send({ data: rows });
        } catch (e) {
            fastify.log.error(e);
            return reply.code(500).send({ error: 'Internal Server Error', message: e.message });
        }
    });
};
