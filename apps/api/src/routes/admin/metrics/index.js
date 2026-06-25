'use strict';

const { query } = require('../../../db/pool');

module.exports = async function metricsRoutes(fastify) {
    const auth = { preHandler: [fastify.authenticate] };

    // GET /api/admin/metrics
    // Optional ?prefix=C  → filters all stats & activity to that prefix
    //                        (also includes any priority-child prefixes automatically)
    fastify.get('/', auth, async (request, reply) => {
        const rawPrefix = request.query.prefix?.trim().toUpperCase() || null;

        // Resolve the full set of prefixes to filter by:
        // the requested prefix + any priority-child prefixes that route into it
        let prefixList = null;
        if (rawPrefix) {
            const { rows: children } = await query(
                `SELECT prefix FROM clinicqueue.queue_settings
                 WHERE is_priority_for = $1 AND archived = false`,
                [rawPrefix]
            );
            prefixList = [rawPrefix, ...children.map(r => r.prefix)];
        }

        // Helper: builds the optional WHERE clause fragment
        // when prefixList is set we use ANY($n::text[])
        const prefixWhere = prefixList
            ? `AND t.prefix = ANY($1::text[])`
            : '';
        const prefixParam = prefixList ? [prefixList] : [];

        // ── Stats (today) ──────────────────────────────────────────────────
        const { rows: statsRows } = await query(`
            SELECT
                COUNT(*) FILTER (WHERE status = 'EN_COLA')                    AS waiting,
                COUNT(*) FILTER (WHERE status IN ('LLAMADO', 'EN_ATENCION'))  AS serving,
                COUNT(*) FILTER (WHERE status = 'FINALIZADO')                 AS done,
                COUNT(*) FILTER (WHERE status = 'NO_SHOW')                    AS no_show
            FROM clinicqueue.tickets t
            WHERE t.created_at >= current_date
            ${prefixWhere}
        `, prefixParam);

        // ── Waiting counts by prefix ───────────────────────────────────────
        // Always returned unfiltered so callers can read any prefix's count
        const { rows: prefixWeights } = await query(`
            SELECT prefix, COUNT(*) AS count
            FROM clinicqueue.tickets
            WHERE status = 'EN_COLA'
              AND created_at >= current_date
            GROUP BY prefix
        `, []);

        // ── Recent activity ────────────────────────────────────────────────
        const { rows: recentTcks } = await query(`
            SELECT
                t.ticket_id,
                t.code       AS ticket_number,
                t.prefix,
                t.status,
                t.called_at,
                t.ended_at,
                s.station_name,
                m.module_name,
                m.module_code
            FROM clinicqueue.tickets t
            LEFT JOIN clinicqueue.stations s ON t.station_id = s.station_id
            LEFT JOIN clinicqueue.modules  m ON t.module_id  = m.module_id
            WHERE t.created_at >= current_date
            ${prefixWhere}
            ORDER BY COALESCE(t.ended_at, t.called_at, t.created_at) DESC
            LIMIT 15
        `, prefixParam);

        // ── Map statuses ───────────────────────────────────────────────────
        const mapStatus = (dbStatus) => {
            switch (dbStatus) {
                case 'EN_COLA':    return 'waiting';
                case 'LLAMADO':
                case 'EN_ATENCION': return 'serving';
                case 'FINALIZADO': return 'done';
                case 'NO_SHOW':    return 'no_show';
                case 'CANCELADO':  return 'cancelled';
                case 'TRANSFERIDO': return 'transferred';
                default:           return 'waiting';
            }
        };

        const stats = {
            waiting: parseInt(statsRows[0]?.waiting  || 0, 10),
            serving: parseInt(statsRows[0]?.serving  || 0, 10),
            done:    parseInt(statsRows[0]?.done     || 0, 10),
            noShow:  parseInt(statsRows[0]?.no_show  || 0, 10),
            waitingByPrefix: prefixWeights.reduce((acc, curr) => {
                acc[curr.prefix] = parseInt(curr.count, 10);
                return acc;
            }, {}),
        };

        return reply.send({
            data: {
                stats,
                tickets: recentTcks.map(t => ({ ...t, status: mapStatus(t.status) })),
            },
        });
    });
};
