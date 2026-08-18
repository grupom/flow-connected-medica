'use strict';

const { query } = require('../../../db/pool');

/**
 * Builds a `WHERE a AND b AND ...` clause (or '' if every part is falsy)
 * plus its positional parameter values, in one pass. Each part is either
 * `null`/`undefined` (skipped), `[sql]` for a condition with no bind value
 * (e.g. a CURRENT_DATE default), or `[sql, value]` where `?` in `sql` is
 * replaced with the correct `$N`.
 *
 * Centralizes what each report endpoint used to hand-roll separately —
 * tracking its own paramIndex and re-deriving which values belong to the
 * WHERE clause vs. trailing params (pagination, etc) via slice() arithmetic
 * tied to a hardcoded parameter count. Here the WHERE-clause values are
 * simply `values`, returned directly — no arithmetic to keep in sync.
 */
function buildWhere(...parts) {
    const conditions = [];
    const values = [];
    for (const part of parts) {
        if (!part) continue;
        const [sql, value] = part;
        if (part.length > 1) {
            values.push(value);
            conditions.push(sql.replace('?', `$${values.length}`));
        } else {
            conditions.push(sql);
        }
    }
    return {
        clause: conditions.length ? `WHERE ${conditions.join(' AND ')}` : '',
        values,
    };
}

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

        const { clause: whereClause, values: whereValues } = buildWhere(
            date ? [`t.ticket_date = ?`, date] : [`t.ticket_date = CURRENT_DATE`],
            status ? [`t.status = ?`, status] : null,
        );

        // Pagination params are separate from the WHERE values so the count
        // query below can reuse whereValues as-is, with no slicing needed.
        const listValues = [...whereValues, limit, offset];
        const limitIndex = whereValues.length + 1;
        const offsetIndex = whereValues.length + 2;

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
        `, listValues);

        // Map statuses to readable ones
        const mapStatus = (db) => {
            switch(db) {
                case 'EN_COLA': return 'En Espera';
                case 'LLAMADO': return 'Llamado';
                case 'EN_ATENCION': return 'Atendiendo';
                case 'FINALIZADO': return 'Finalizado';
                case 'NO_SHOW': return 'No-Show';
                case 'CANCELADO': return 'Cancelado';
                case 'TRANSFERIDO': return 'Transferido';
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
        `, whereValues);

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

        const { clause: whereClause, values } = buildWhere(
            date ? [`t.ticket_date = ?`, date] : [`t.ticket_date = CURRENT_DATE`],
            [`t.called_at IS NOT NULL`],
        );

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
            ${whereClause}
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

        const { clause: whereClause, values } = buildWhere(
            start ? [`t.ticket_date >= ?`, start] : null,
            end ? [`t.ticket_date <= ?`, end] : null,
        );

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

        const { clause: whereClause, values } = buildWhere(
            date ? [`t.ticket_date = ?`, date] : [`t.ticket_date = CURRENT_DATE`],
        );

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
            ${whereClause}
            GROUP BY ${groupColumn}
            ORDER BY total_issued DESC
        `, values);

        return reply.send(rows);
    });
};
