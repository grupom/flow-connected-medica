'use strict';

const { query } = require('../../db/pool');

module.exports = async function boardsPublicRoutes(fastify) {
    // GET /api/boards/:boardCode/snapshot  — public (no auth needed for display screens)
    fastify.get('/:boardCode/snapshot', {
        schema: {
            params: {
                type: 'object',
                properties: { boardCode: { type: 'string' } },
            },
        },
    }, async (request, reply) => {
        const { boardCode } = request.params;
        const { rows } = await query(
            `SELECT clinicqueue.get_board_snapshot($1) AS snapshot`,
            [boardCode.toUpperCase()]
        );
        const snapshot = rows[0]?.snapshot;
        if (!snapshot) {
            return reply.code(404).send({ error: 'Not Found', message: `Board "${boardCode}" not found` });
        }

        // station_name is the primary display label (returned directly by get_board_snapshot)
        // module_name is no longer used — modules are optional organizational metadata

        return reply.send(snapshot);
    });
};
