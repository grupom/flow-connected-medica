'use strict';

const { query } = require('../../db/pool');

module.exports = async function myStationsRoutes(fastify) {
    const auth = { preHandler: [fastify.authenticate] };

    // GET /api/my-stations — returns only stations the current user is authorized to operate
    fastify.get('/', auth, async (request, reply) => {
        const userId = request.user.user_id;
        const { rows } = await query(
            `SELECT s.station_id, s.station_code, s.station_name, s.prefix, s.is_active,
                    m.module_id, m.module_name, m.module_code
             FROM clinicqueue.station_users su
             JOIN clinicqueue.stations s ON s.station_id = su.station_id
             LEFT JOIN clinicqueue.modules m ON m.module_id = s.module_id
             WHERE su.user_id = $1
               AND su.is_enabled = true
               AND s.is_active = true
             ORDER BY s.station_name`,
            [userId]
        );
        return reply.send({ data: rows });
    });
};
