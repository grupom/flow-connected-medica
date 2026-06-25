'use strict';

const { query } = require('../../../db/pool');

module.exports = async function reportsRoutes(fastify) {
    const auth = { preHandler: [fastify.authenticate] };

    // GET /api/admin/reports/tickets
    fastify.get('/tickets', {
        ...auth,
        schema: {
            querystring: {
                type: 'object',
                properties: {
                    date: { type: 'string', format: 'date' }, // YYYY-MM-DD
                    status: { type: 'string' },
                    limit: { type: 'integer', default: 100 },
                    offset: { type: 'integer', default: 0 },
                },
            },
        },
    }, async (request, reply) => {
        const { date, status, limit, offset } = request.query;
        
        // Build WHERE clause dynamically
        const conditions = [];
        const values = [];
        let paramIndex = 1;

        if (date) {
            conditions.push(`t.ticket_date = $${paramIndex++}`);
            values.push(date);
        } else {
            // Default to today if no date provided
            conditions.push(`t.ticket_date = CURRENT_DATE`);
        }

        if (status) {
            conditions.push(`t.status = $${paramIndex++}`);
            values.push(status);
        }

        const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

        // Add pagination values
        values.push(limit);
        const limitIndex = paramIndex++;
        values.push(offset);
        const offsetIndex = paramIndex++;

        // Query tickets
        const { rows } = await query(`
            SELECT 
                t.ticket_id,
                t.code AS ticket_number,
                t.status,
                t.created_at,
                t.called_at,
                t.started_at,
                t.ended_at,
                s.station_name,
                COALESCE(m.module_name, s.station_name) AS module_name,
                EXTRACT(EPOCH FROM (t.called_at - t.created_at)) / 60 AS wait_time_mins,
                EXTRACT(EPOCH FROM (t.ended_at - COALESCE(t.started_at, t.called_at))) / 60 AS service_time_mins
            FROM clinicqueue.tickets t
            LEFT JOIN clinicqueue.stations s ON t.station_id = s.station_id
            LEFT JOIN clinicqueue.modules m ON t.module_id = m.module_id
            ${whereClause}
            ORDER BY t.created_at DESC
            LIMIT $${limitIndex} OFFSET $${offsetIndex}
        `, values);

        // Map statuses to readable ones
        const mapStatus = (db) => {
            switch(db) {
                case 'EN_COLA': return 'Waiting';
                case 'LLAMADO': return 'Called';
                case 'EN_ATENCION': return 'Serving';
                case 'FINALIZADO': return 'Done';
                case 'NO_SHOW': return 'No-Show';
                case 'CANCELADO': return 'Cancelled';
                case 'TRANSFERIDO': return 'Transferred';
                default: return db;
            }
        };

        const mapped = rows.map(t => ({
            ...t,
            status_nice: mapStatus(t.status),
            wait_time_mins: t.wait_time_mins ? Math.round(t.wait_time_mins) : null,
            service_time_mins: t.service_time_mins ? Math.round(t.service_time_mins) : null
        }));

        // Get total count for pagination
        const { rows: countRows } = await query(`
            SELECT COUNT(*) AS total
            FROM clinicqueue.tickets t
            ${whereClause}
        `, values.slice(0, paramIndex - 3)); // Pass only the WHERE values

        return reply.send({ 
            data: mapped, 
            meta: { 
                total: parseInt(countRows[0].total, 10),
                limit, 
                offset 
            } 
        });
    });

    // GET /api/admin/reports/waiting-time
    fastify.get('/waiting-time', {
        ...auth,
        schema: {
            querystring: {
                type: 'object',
                properties: {
                    date: { type: 'string', format: 'date' }
                }
            }
        }
    }, async (request, reply) => {
        const { date } = request.query;
        let dateCondition = "t.ticket_date = CURRENT_DATE";
        const values = [];

        if (date) {
            values.push(date);
            dateCondition = "t.ticket_date = $1";
        }

        const { rows } = await query(`
            SELECT 
                COALESCE(m.module_name, s.station_name, 'Desconocido') AS group_name,
                m.module_name,
                s.station_name,
                COUNT(t.ticket_id) AS total_tickets,
                ROUND(AVG(EXTRACT(EPOCH FROM (t.called_at - t.created_at))) / 60) AS avg_wait_min,
                ROUND(MIN(EXTRACT(EPOCH FROM (t.called_at - t.created_at))) / 60) AS min_wait_min,
                ROUND(MAX(EXTRACT(EPOCH FROM (t.called_at - t.created_at))) / 60) AS max_wait_min
            FROM clinicqueue.tickets t
            LEFT JOIN clinicqueue.stations s ON t.station_id = s.station_id
            LEFT JOIN clinicqueue.modules m ON t.module_id = m.module_id
            WHERE ${dateCondition}
              AND t.called_at IS NOT NULL
            GROUP BY m.module_name, s.station_name
            ORDER BY avg_wait_min DESC NULLS LAST
        `, values);

        return reply.send(rows);
    });

    // GET /api/admin/reports/congestion-demand
    fastify.get('/congestion-demand', {
        ...auth,
        schema: {
            querystring: {
                type: 'object',
                properties: {
                    start: { type: 'string', format: 'date' },
                    end: { type: 'string', format: 'date' }
                }
            }
        }
    }, async (request, reply) => {
        const { start, end } = request.query;
        let conditions = [];
        const values = [];
        let pIdx = 1;

        if (start) {
            conditions.push(`t.ticket_date >= $${pIdx++}`);
            values.push(start);
        }
        if (end) {
            conditions.push(`t.ticket_date <= $${pIdx++}`);
            values.push(end);
        }

        const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

        const { rows } = await query(`
            SELECT 
                TO_CHAR(t.created_at, 'YYYY-MM-DD') AS log_date,
                EXTRACT(HOUR FROM t.created_at) AS log_hour,
                COUNT(t.ticket_id) AS total_tickets
            FROM clinicqueue.tickets t
            ${whereClause}
            GROUP BY TO_CHAR(t.created_at, 'YYYY-MM-DD'), EXTRACT(HOUR FROM t.created_at)
            ORDER BY log_date DESC, log_hour DESC
        `, values);

        return reply.send(rows);
    });

    // GET /api/admin/reports/tickets-by-station-area
    fastify.get('/tickets-by-station-area', {
        ...auth,
        schema: {
            querystring: {
                type: 'object',
                properties: {
                    date: { type: 'string', format: 'date' },
                    groupBy: { type: 'string', enum: ['module', 'station'], default: 'module' }
                }
            }
        }
    }, async (request, reply) => {
        const { date, groupBy } = request.query;
        
        const isModule = groupBy === 'module';
        const groupColumn = isModule ? 'm.module_name' : 's.station_name';
        
        let dateCondition = "t.ticket_date = CURRENT_DATE";
        const values = [];

        if (date) {
            values.push(date);
            dateCondition = "t.ticket_date = $1";
        }

        const { rows } = await query(`
            SELECT 
                COALESCE(${groupColumn}, 'Sin Asignar') AS group_name,
                COUNT(t.ticket_id) AS total_issued,
                SUM(CASE WHEN t.status IN ('FINALIZADO') THEN 1 ELSE 0 END) AS done_count,
                SUM(CASE WHEN t.status IN ('EN_COLA', 'LLAMADO') THEN 1 ELSE 0 END) AS waiting_count,
                SUM(CASE WHEN t.status IN ('NO_SHOW', 'CANCELADO') THEN 1 ELSE 0 END) AS noshow_count
            FROM clinicqueue.tickets t
            LEFT JOIN clinicqueue.stations s ON t.station_id = s.station_id
            LEFT JOIN clinicqueue.modules m ON t.module_id = m.module_id
            WHERE ${dateCondition}
            GROUP BY ${groupColumn}
            ORDER BY total_issued DESC
        `, values);

        return reply.send(rows);
    });
};
