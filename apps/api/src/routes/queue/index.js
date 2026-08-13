'use strict';

const svc = require('./service');

const bodyWithTicketId = {
    schema: {
        body: {
            type: 'object',
            required: ['ticket_id', 'station_id', 'user_id'],
            properties: {
                ticket_id: { type: 'integer' },
                station_id: { type: 'integer' },
                user_id: { type: 'integer' },
                reason: { type: 'string' },
                notes: { type: 'string' },
            },
        },
    },
};

module.exports = async function queueRoutes(fastify) {
    const auth = { preHandler: [fastify.authenticate] };
    const { query } = require('../../db/pool');

    // GET /api/queue/queue-settings — active queues, staff-safe subset of
    // /api/admin/queue-settings (no admin role required). Used by front-desk
    // and station operators to populate service/transfer pickers; excludes
    // config-only fields (mode, min/max_number, timeouts, etc.) they don't need.
    fastify.get('/queue-settings', auth, async (request, reply) => {
        const { rows } = await query(
            `SELECT prefix, service_name, icon, allow_walkins, is_priority_for
             FROM clinicqueue.queue_settings
             WHERE archived = false
             ORDER BY prefix`
        );
        return reply.send({ data: rows });
    });

    // GET /api/queue/active-ticket/:stationId — find any LLAMADO/EN_SERVICIO ticket at this station
    fastify.get('/active-ticket/:stationId', {
        ...auth,
        schema: { params: { type: 'object', properties: { stationId: { type: 'integer' } } } },
    }, async (request, reply) => {
        const { stationId } = request.params;
        const { rows } = await query(
            `SELECT t.ticket_id, t.code, t.status,
                    t.called_at, t.started_at, t.created_at,
                    s.station_name AS module_name, m.module_code
             FROM clinicqueue.tickets t
             LEFT JOIN clinicqueue.stations s ON s.station_id = t.station_id
             LEFT JOIN clinicqueue.modules m ON m.module_id = s.module_id
             WHERE t.station_id = $1
               AND t.status IN ('LLAMADO', 'EN_ATENCION')
             ORDER BY t.called_at DESC NULLS LAST
             LIMIT 1`,
            [stationId]
        );
        return reply.send({ data: rows[0] || null });
    });

    // POST /api/queue/create-ticket
    fastify.post('/create-ticket', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                required: ['prefix', 'created_by'],
                properties: {
                    prefix: { type: 'string' },
                    created_by: { type: 'integer' },
                    is_walkin: { type: 'boolean' },
                },
            },
        },
    }, async (request, reply) => {
        const ticket = await svc.createTicket(request.body);
        return reply.code(201).send({ data: ticket });
    });

    // POST /api/queue/call-next
    fastify.post('/call-next', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                required: ['station_id', 'user_id'],
                properties: {
                    station_id: { type: 'integer' },
                    user_id: { type: 'integer' },
                },
            },
        },
    }, async (request, reply) => {
        const ticket = await svc.callNext(request.body);
        return reply.send({ data: ticket });
    });

    // POST /api/queue/start
    fastify.post('/start', { ...auth, ...bodyWithTicketId }, async (request, reply) => {
        const ticket = await svc.startTicket({ ...request.body, user_id: request.user.user_id });
        return reply.send({ data: ticket });
    });

    // POST /api/queue/recall
    fastify.post('/recall', { ...auth, ...bodyWithTicketId }, async (request, reply) => {
        const ticket = await svc.recallTicket({ ...request.body, user_id: request.user.user_id });
        return reply.send({ data: ticket });
    });

    // POST /api/queue/finish
    fastify.post('/finish', { ...auth, ...bodyWithTicketId }, async (request, reply) => {
        const ticket = await svc.finishTicket({ ...request.body, user_id: request.user.user_id });
        return reply.send({ data: ticket });
    });

    // POST /api/queue/cancel
    fastify.post('/cancel', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                required: ['ticket_id', 'user_id'],
                properties: {
                    ticket_id: { type: 'integer' },
                    user_id: { type: 'integer' },
                    reason: { type: 'string' },
                },
            },
        },
    }, async (request, reply) => {
        const ticket = await svc.cancelTicket({ ...request.body, user_id: request.user.user_id });
        return reply.send({ data: ticket });
    });

    // POST /api/queue/no-show
    fastify.post('/no-show', { ...auth, ...bodyWithTicketId }, async (request, reply) => {
        const ticket = await svc.noShowTicket({ ...request.body, user_id: request.user.user_id });
        return reply.send({ data: ticket });
    });

    // POST /api/queue/transfer
    fastify.post('/transfer', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                required: ['ticket_id', 'station_id', 'user_id', 'to_prefix'],
                properties: {
                    ticket_id: { type: 'integer' },
                    station_id: { type: 'integer' },
                    user_id: { type: 'integer' },
                    to_prefix: { type: 'string' },
                    reason: { type: 'string' },
                },
            },
        },
    }, async (request, reply) => {
        const ticket = await svc.transferTicket({ ...request.body, user_id: request.user.user_id });
        return reply.send({ data: ticket });
    });

    // POST /api/queue/transfer-multi — close out a called/in-attention ticket
    // and split it into a multi-area visit plan (2+ new tickets).
    fastify.post('/transfer-multi', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                required: ['ticket_id', 'station_id', 'to_prefixes'],
                properties: {
                    ticket_id: { type: 'integer' },
                    station_id: { type: 'integer' },
                    to_prefixes: { type: 'array', minItems: 2, items: { type: 'string' } },
                    reason: { type: 'string' },
                },
            },
        },
    }, async (request, reply) => {
        const plan = await svc.transferTicketMultiArea({ ...request.body, user_id: request.user.user_id });
        return reply.code(201).send({ data: plan });
    });

    // POST /api/queue/visit-plan — pre-register a patient into an ordered
    // chain of 2+ queues; only the first step's ticket is created now.
    fastify.post('/visit-plan', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                required: ['created_by', 'steps'],
                properties: {
                    created_by: { type: 'integer' },
                    steps: {
                        type: 'array',
                        minItems: 2,
                        items: {
                            type: 'object',
                            required: ['prefix'],
                            properties: { prefix: { type: 'string' } },
                        },
                    },
                },
            },
        },
    }, async (request, reply) => {
        const plan = await svc.createVisitPlan(request.body);
        return reply.code(201).send({ data: plan });
    });

    // GET /api/queue/no-show?station_id=X — list today's NO_SHOW tickets for
    // this station's queue, each annotated with eligibility to be requeued.
    fastify.get('/no-show', {
        ...auth,
        schema: {
            querystring: {
                type: 'object',
                required: ['station_id'],
                properties: { station_id: { type: 'integer' } },
            },
        },
    }, async (request, reply) => {
        const list = await svc.listNoShowTickets({
            station_id: request.query.station_id,
            user_id: request.user.user_id,
        });
        return reply.send({ data: list });
    });

    // POST /api/queue/requeue-no-show — put a NO_SHOW ticket back into EN_COLA.
    fastify.post('/requeue-no-show', { ...auth, ...bodyWithTicketId }, async (request, reply) => {
        const ticket = await svc.requeueNoShowTicket(request.body);
        return reply.send({ data: ticket });
    });

    // POST /api/queue/auto-no-show/run  (admin only)
    fastify.post('/auto-no-show/run', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                properties: { limit: { type: 'integer', default: 50 } },
            },
        },
    }, async (request, reply) => {
        const result = await svc.autoNoShow(request.body.limit);
        return reply.send({ data: result });
    });
};
