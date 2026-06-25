'use strict';

const { query } = require('../../db/pool');

// Public route — no authentication required
module.exports = async function publicSettingsRoutes(fastify) {
    // GET /api/settings
    fastify.get('/', async (_request, reply) => {
        const { rows } = await query(
            `SELECT key, value FROM clinicqueue.system_settings ORDER BY key`
        );
        const data = Object.fromEntries(rows.map(r => [r.key, r.value]));
        return reply.send({ data });
    });
};
