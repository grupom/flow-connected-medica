'use strict';

const svc = require('./service');

module.exports = async function kioskRoutes(fastify) {
    // Authenticated API for Kiosks
    const auth = { preHandler: [fastify.authenticate] };

    // GET /api/kiosk/session
    // Returns information about the currently authenticated Kiosk and its allowed queues
    fastify.get('/session', {
        ...auth,
    }, async (request, reply) => {
        const userId = request.user.user_id; // from JWT token
        const kioskData = await svc.getKioskSession(userId);
        
        if (!kioskData) {
            return reply.code(403).send({ 
                error: 'FORBIDDEN', 
                message: 'User is not linked to any active Kiosk' 
            });
        }
        
        return reply.send({ data: kioskData });
    });

    // POST /api/kiosk/issue-ticket
    // Securely issues a ticket ensuring the Kiosk is authorized for the requested prefix
    fastify.post('/issue-ticket', {
        ...auth,
        schema: {
            body: {
                type: 'object',
                required: ['prefix'],
                properties: {
                    prefix: { type: 'string' }
                }
            }
        }
    }, async (request, reply) => {
        const userId = request.user.user_id;
        const { prefix } = request.body;
        
        try {
            const ticket = await svc.issueKioskTicket(userId, prefix);
            return reply.code(201).send({ data: ticket });
        } catch (error) {
            if (error.statusCode === 403) {
                return reply.code(403).send({ error: 'FORBIDDEN', message: error.message });
            }
            throw error;
        }
    });
};
