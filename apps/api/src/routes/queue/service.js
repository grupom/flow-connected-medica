'use strict';

const { query, transaction } = require('../../db/pool');

/**
 * Create a new ticket in the queue.
 */
async function createTicket({ prefix, created_by, is_walkin }) {
    const { rows } = await query(
        `SELECT * FROM clinicqueue.create_ticket($1, $2, $3)`,
        [prefix, created_by, is_walkin ?? true]
    );
    // The DB function handles the insert, counter logic, and event logging.
    const dbResult = rows[0];
    if (!dbResult) return null;
    
    // Fetch service_name and current time for printing
    const { rows: sRows } = await query(`SELECT service_name FROM clinicqueue.queue_settings WHERE prefix = $1`, [prefix]);
    const serviceName = sRows[0]?.service_name || prefix;
    
    const code = dbResult.out_code || dbResult.code;

    return {
        ticket_id: dbResult.out_ticket_id || dbResult.ticket_id,
        prefix: dbResult.out_prefix || dbResult.prefix,
        tck_number: dbResult.out_tck_number || dbResult.tck_number,
        code: code,
        status: dbResult.out_status || dbResult.status,
        service_name: serviceName
    };
}

/**
 * Call the next waiting ticket for a station.
 * Uses the DB stored procedure which handles:
 * - station validation & authorization
 * - 1 LLAMADO per station enforcement
 * - module_id assignment
 * - event logging
 */
async function callNext({ station_id, user_id }) {
    const { rows } = await query(
        `SELECT * FROM clinicqueue.call_next_ticket($1, $2)`,
        [station_id, user_id]
    );
    if (!rows.length) {
        const err = new Error('No hay tickets esperando para esta área');
        err.statusCode = 404;
        throw err;
    }
    const r = rows[0];
    // Enrich with module_name, fallback to station_name if no module assigned (Option C)
    const stationId = r.out_station_id || r.station_id;
    const { rows: modRows } = await query(
        `SELECT m.module_name, s.station_name
         FROM clinicqueue.stations s
         LEFT JOIN clinicqueue.modules m ON m.module_id = s.module_id
         WHERE s.station_id = $1`,
        [stationId]
    );
    return {
        ticket_id: r.out_ticket_id || r.ticket_id,
        code: r.out_code || r.code,
        prefix: r.out_prefix || r.prefix,
        tck_number: r.out_tck_number || r.tck_number,
        module_id: r.out_module_id || r.module_id,
        module_name: modRows[0]?.station_name || null,
        station_id: stationId,
        status: r.out_status || r.status,
        called_at: r.out_called_at || r.called_at,
    };
}

/**
 * Start service on a ticket.
 */
async function startTicket({ ticket_id, station_id, user_id }) {
    await assertStationAccess(query, station_id, user_id);
    const { rows } = await query(
        `UPDATE clinicqueue.tickets
     SET status = 'EN_ATENCION', started_at = now(), started_by = $2
     WHERE ticket_id = $1 AND station_id = $3 AND status = 'LLAMADO'
     RETURNING *`,
        [ticket_id, user_id, station_id]
    );
    if (!rows.length) throw Object.assign(new Error('Ticket not found or wrong status'), { statusCode: 404 });
    await query(
        `INSERT INTO clinicqueue.ticket_events (ticket_id, station_id, event_type, from_status, to_status, user_id) VALUES ($1, $2, 'STARTED', 'LLAMADO', 'EN_ATENCION', $3)`,
        [ticket_id, station_id, user_id]
    );
    return rows[0];
}

/**
 * Recall a ticket (re-announce).
 */
async function recallTicket({ ticket_id, station_id, user_id, reason }) {
    await assertStationAccess(query, station_id, user_id);
    const { rows } = await query(
        `UPDATE clinicqueue.tickets SET called_at = now() WHERE ticket_id = $1 AND station_id = $2 AND status = 'LLAMADO' RETURNING *`,
        [ticket_id, station_id]
    );
    if (!rows.length) throw Object.assign(new Error('Ticket not in LLAMADO state'), { statusCode: 409 });
    await query(
        `INSERT INTO clinicqueue.ticket_events (ticket_id, station_id, event_type, from_status, to_status, details, user_id) VALUES ($1, $2, 'RECALLED', 'LLAMADO', 'LLAMADO', $3, $4)`,
        [ticket_id, station_id, reason ? JSON.stringify({ reason }) : null, user_id]
    );
    return rows[0];
}

/**
 * Finish service on a ticket.
 */
async function finishTicket({ ticket_id, station_id, user_id, notes }) {
    return transaction(async (client) => {
        await assertStationAccess((sql, params) => client.query(sql, params), station_id, user_id);
        const { rows } = await client.query(
            `UPDATE clinicqueue.tickets
         SET status = 'FINALIZADO', ended_at = now(), ended_by = $2
         WHERE ticket_id = $1 AND station_id = $3 AND status = 'EN_ATENCION'
         RETURNING *`,
            [ticket_id, user_id, station_id]
        );
        if (!rows.length) throw Object.assign(new Error('Ticket not in EN_ATENCION state'), { statusCode: 409 });
        const finished = rows[0];

        await client.query(
            `INSERT INTO clinicqueue.ticket_events (ticket_id, station_id, event_type, from_status, to_status, details, user_id) VALUES ($1, $2, 'FINISHED', 'EN_ATENCION', 'FINALIZADO', $3, $4)`,
            [ticket_id, station_id, notes ? JSON.stringify({ notes }) : null, user_id]
        );

        return finished;
    });
}

/**
 * Create a multi-queue visit plan: a patient pre-registered at intake/billing
 * for 2+ areas in the same visit (e.g. Laboratorio + Imágenes). All steps'
 * tickets are created immediately and enter EN_COLA at once — there's no
 * assumed visit order, since the patient decides which area to visit first
 * and how long to spend between them.
 */
async function createVisitPlan({ created_by, steps }) {
    if (!Array.isArray(steps) || steps.length < 2) {
        throw Object.assign(new Error('Un plan de visita requiere al menos 2 áreas; use /create-ticket para una sola cola'), { statusCode: 400 });
    }
    const prefixes = steps.map((s) => String(s.prefix).trim().toUpperCase());
    if (new Set(prefixes).size !== prefixes.length) {
        throw Object.assign(new Error('No se puede repetir la misma cola dentro de un mismo plan'), { statusCode: 400 });
    }

    return transaction(async (client) => {
        const { rows: qsRows } = await client.query(
            `SELECT prefix, service_name FROM clinicqueue.queue_settings WHERE prefix = ANY($1) AND archived = false`,
            [prefixes]
        );
        const found = new Map(qsRows.map((r) => [r.prefix, r.service_name]));
        const missing = prefixes.filter((p) => !found.has(p));
        if (missing.length) {
            throw Object.assign(new Error(`Cola(s) inválida(s) o archivada(s): ${missing.join(', ')}`), { statusCode: 400 });
        }

        const { rows: planRows } = await client.query(
            `INSERT INTO clinicqueue.visit_plans (created_by) VALUES ($1) RETURNING visit_plan_id`,
            [created_by]
        );
        const visitPlanId = planRows[0].visit_plan_id;

        const tickets = [];
        for (let i = 0; i < prefixes.length; i++) {
            const prefix = prefixes[i];
            const { rows: stepRows } = await client.query(
                `INSERT INTO clinicqueue.visit_plan_steps (visit_plan_id, step_order, prefix)
                 VALUES ($1, $2, $3) RETURNING step_id`,
                [visitPlanId, i + 1, prefix]
            );
            const stepId = stepRows[0].step_id;

            const { rows: tRows } = await client.query(
                `SELECT * FROM clinicqueue.create_ticket($1, $2, $3)`,
                [prefix, created_by, false]
            );
            const dbResult = tRows[0];
            const ticketId = dbResult.out_ticket_id;

            await client.query(
                `UPDATE clinicqueue.ticket_events SET details = COALESCE(details, '{}'::jsonb) || $2::jsonb
                 WHERE ticket_id = $1 AND event_type = 'CREATED'`,
                [ticketId, JSON.stringify({ visit_plan_id: visitPlanId, step_order: i + 1 })]
            );
            await client.query(`UPDATE clinicqueue.tickets SET visit_plan_id = $1 WHERE ticket_id = $2`, [visitPlanId, ticketId]);
            await client.query(`UPDATE clinicqueue.visit_plan_steps SET ticket_id = $1 WHERE step_id = $2`, [ticketId, stepId]);

            tickets.push({
                ticket_id: ticketId,
                prefix: dbResult.out_prefix,
                tck_number: dbResult.out_tck_number,
                code: dbResult.out_code,
                status: dbResult.out_status,
                service_name: found.get(prefix),
            });
        }

        return { visit_plan_id: visitPlanId, tickets };
    });
}

/**
 * Cancel a ticket.
 */
async function cancelTicket({ ticket_id, user_id, reason }) {
    // get old status + current station (read from the ticket itself, never
    // trusted from the client, so it can't be spoofed to dodge the check below)
    const { rows: tRows } = await query(`SELECT status, station_id FROM clinicqueue.tickets WHERE ticket_id = $1`, [ticket_id]);
    if (!tRows.length) throw Object.assign(new Error('Ticket not found'), { statusCode: 404 });
    const { status: fromStatus, station_id } = tRows[0];

    // A ticket still EN_COLA has no station yet (anyone can cancel it); once
    // called/attended it belongs to a station and only that station's staff may cancel it.
    if (station_id) {
        await assertStationAccess(query, station_id, user_id);
    }

    const { rows } = await query(
        `UPDATE clinicqueue.tickets
     SET status = 'CANCELADO'
     WHERE ticket_id = $1 AND status IN ('EN_COLA', 'LLAMADO', 'EN_ATENCION')
     RETURNING *`,
        [ticket_id]
    );
    if (!rows.length) throw Object.assign(new Error('Ticket already closed or wrong status'), { statusCode: 409 });
    await query(
        `INSERT INTO clinicqueue.ticket_events (ticket_id, event_type, from_status, to_status, details, user_id) VALUES ($1, 'CANCELLED', $2, 'CANCELADO', $3, $4)`,
        [ticket_id, fromStatus, reason ? JSON.stringify({ reason }) : null, user_id]
    );
    return rows[0];
}

/**
 * Mark ticket as no-show.
 */
async function noShowTicket({ ticket_id, station_id, user_id, reason }) {
    await assertStationAccess(query, station_id, user_id);
    const { rows } = await query(
        `UPDATE clinicqueue.tickets
     SET status = 'NO_SHOW'
     WHERE ticket_id = $1 AND station_id = $2 AND status = 'LLAMADO'
     RETURNING *`,
        [ticket_id, station_id]
    );
    if (!rows.length) throw Object.assign(new Error('Ticket not in LLAMADO state'), { statusCode: 409 });
    await query(
        `INSERT INTO clinicqueue.ticket_events (ticket_id, station_id, event_type, from_status, to_status, details, user_id) VALUES ($1, $2, 'NO_SHOW', 'LLAMADO', 'NO_SHOW', $3, $4)`,
        [ticket_id, station_id, reason ? JSON.stringify({ reason }) : null, user_id]
    );
    return rows[0];
}

/**
 * Transfer a ticket to a new prefix.
 */
async function transferTicket({ ticket_id, station_id, user_id, to_prefix, reason }) {
    return transaction(async (client) => {
        const exec = (sql, params) => client.query(sql, params);
        await assertStationAccess(exec, station_id, user_id);

        // 1. Get current ticket
        const { rows: tRows } = await client.query(
            `SELECT * FROM clinicqueue.tickets WHERE ticket_id = $1 AND station_id = $2 FOR UPDATE`,
            [ticket_id, station_id]
        );
        if (!tRows.length) throw Object.assign(new Error('Ticket not found'), { statusCode: 404 });
        const oldTicket = tRows[0];

        // 2. Allocate new number for destination prefix safely
        const { rows: qsRows } = await client.query(
            `SELECT mode, min_number, max_number FROM clinicqueue.queue_settings WHERE prefix = $1`,
            [to_prefix]
        );
        if (!qsRows.length) throw Object.assign(new Error('Destination prefix not found'), { statusCode: 400 });
        const { mode, min_number, max_number } = qsRows[0];
        const counterKey = mode === 'DAILY_RESET' ? new Date().toISOString().split('T')[0] : 'GLOBAL';

        await client.query(
            `INSERT INTO clinicqueue.queue_counters(prefix, counter_key, last_number) VALUES ($1, $2, 0) ON CONFLICT DO NOTHING`,
            [to_prefix, counterKey]
        );
        const { rows: cRows } = await client.query(
            `SELECT last_number FROM clinicqueue.queue_counters WHERE prefix = $1 AND counter_key = $2 FOR UPDATE`,
            [to_prefix, counterKey]
        );
        
        let candidate = cRows[0].last_number + 1;
        if (candidate > max_number || candidate < min_number) candidate = min_number;

        await client.query(
            `UPDATE clinicqueue.queue_counters SET last_number = $3, updated_at = now() WHERE prefix = $1 AND counter_key = $2`,
            [to_prefix, counterKey, candidate]
        );

        const newCode = to_prefix + String(candidate).padStart(2, '0');

        // 3. Mutate the ticket
        const { rows } = await client.query(
            `UPDATE clinicqueue.tickets
             SET prefix = $2, tck_number = $3, code = $4, status = 'EN_COLA', 
                 station_id = null, module_id = null
             WHERE ticket_id = $1
             RETURNING *`,
            [ticket_id, to_prefix, candidate, newCode]
        );

        // 4. Log transfer & event
        await client.query(
            `INSERT INTO clinicqueue.ticket_transfers 
             (ticket_id, from_prefix, from_station_id, to_prefix, transferred_by, reason)
             VALUES ($1, $2, $3, $4, $5, $6)`,
            [ticket_id, oldTicket.prefix, station_id, to_prefix, user_id, reason || null]
        );

        await client.query(
            `INSERT INTO clinicqueue.ticket_events (ticket_id, station_id, event_type, from_status, to_status, details, user_id)
             VALUES ($1, $2, 'TRANSFERRED', $3, $4, $5, $6)`,
            [ticket_id, station_id, oldTicket.status, 'EN_COLA', reason ? { reason } : null, user_id]
        );

        return rows[0];
    });
}

/**
 * Run auto-no-show batch.
 */
async function autoNoShow(limit) {
    const { rows } = await query(
        `SELECT clinicqueue.auto_no_show($1) AS processed`,
        [limit || 50]
    );
    return rows[0];
}

/**
 * Verify the requesting user is authorized to operate this station (assigned
 * via station_users, within its valid window) and return the station's
 * prefix. Throws 404 if the station doesn't exist/is inactive, 403 if the
 * user isn't assigned to it. `exec` is a (sql, params) => {rows} callable —
 * either the pool's `query` or a transaction client's `.query` bound to it —
 * both share the same call signature.
 */
async function assertStationAccess(exec, station_id, user_id) {
    const { rows: stRows } = await exec(
        `SELECT prefix FROM clinicqueue.stations WHERE station_id = $1 AND is_active = true`,
        [station_id]
    );
    if (!stRows.length) throw Object.assign(new Error('Station not found or inactive'), { statusCode: 404 });

    const { rows: authRows } = await exec(
        `SELECT 1 FROM clinicqueue.station_users
         WHERE station_id = $1 AND user_id = $2 AND is_enabled = true
           AND (valid_from IS NULL OR valid_from <= now())
           AND (valid_to   IS NULL OR valid_to   > now())`,
        [station_id, user_id]
    );
    if (!authRows.length) throw Object.assign(new Error('No autorizado para operar esta estación'), { statusCode: 403 });

    return stRows[0].prefix;
}

/**
 * Read the admin-configured no-show requeue limit (default 3, no seeded row —
 * same fallback convention as session_duration_hours_staff).
 */
async function getNoShowRequeueLimit(exec) {
    const { rows } = await exec(
        `SELECT value FROM clinicqueue.system_settings WHERE key = 'no_show_requeue_limit'`
    );
    return Number(rows[0]?.value) || 3;
}

/**
 * List today's NO_SHOW tickets for a station's queue (prefix), each annotated
 * with how many tickets have already been called after it ("gap") and
 * whether it's still eligible to be requeued under the admin-configured limit.
 */
async function listNoShowTickets({ station_id, user_id }) {
    const prefix = await assertStationAccess(query, station_id, user_id);
    const limit = await getNoShowRequeueLimit(query);

    const { rows } = await query(
        `WITH latest_called AS (
             SELECT MAX(tck_number) AS max_num
             FROM clinicqueue.tickets
             WHERE prefix = $1
               AND ticket_date = current_date
               AND status IN ('LLAMADO','EN_ATENCION','FINALIZADO','NO_SHOW')
         )
         SELECT t.ticket_id, t.code, t.tck_number, t.status, t.called_at, t.created_at, t.visit_plan_id,
                GREATEST(COALESCE(lc.max_num, t.tck_number) - t.tck_number, 0) AS gap
         FROM clinicqueue.tickets t, latest_called lc
         WHERE t.prefix = $1
           AND t.ticket_date = current_date
           AND t.status = 'NO_SHOW'
         ORDER BY t.tck_number ASC`,
        [prefix]
    );

    // Tickets that belong to a multi-area visit plan are exempt from the gap
    // limit — the patient being elsewhere in the same visit is expected, not
    // a real no-show.
    return rows.map((r) => ({ ...r, gap: Number(r.gap), eligible: r.visit_plan_id != null || Number(r.gap) <= limit }));
}

/**
 * Requeue a NO_SHOW ticket back into EN_COLA so it can be called again.
 * created_at is intentionally left untouched — call_next_ticket orders purely
 * by created_at ASC, so the ticket naturally resurfaces ahead of anything
 * created after it, with no special ordering logic needed. module_id must be
 * cleared: call_next_ticket only considers tickets with module_id IS NULL.
 *
 * The gap/limit check is re-verified here (not trusted from an earlier list
 * fetch) and done inside a transaction with FOR UPDATE on the ticket row, to
 * close the race where more tickets get called between listing and requeueing.
 */
async function requeueNoShowTicket({ ticket_id, station_id, user_id }) {
    return transaction(async (client) => {
        const exec = (sql, params) => client.query(sql, params);
        const prefix = await assertStationAccess(exec, station_id, user_id);

        const { rows: tRows } = await client.query(
            `SELECT ticket_id, tck_number, visit_plan_id FROM clinicqueue.tickets
             WHERE ticket_id = $1 AND prefix = $2 AND status = 'NO_SHOW' AND ticket_date = current_date
             FOR UPDATE`,
            [ticket_id, prefix]
        );
        if (!tRows.length) {
            throw Object.assign(new Error('Turno no encontrado, no está en No-Show, o no pertenece a esta cola'), { statusCode: 404 });
        }
        const tckNumber = tRows[0].tck_number;
        const belongsToVisitPlan = tRows[0].visit_plan_id != null;

        const { rows: gapRows } = await client.query(
            `SELECT MAX(tck_number) AS max_num FROM clinicqueue.tickets
             WHERE prefix = $1 AND ticket_date = current_date
               AND status IN ('LLAMADO','EN_ATENCION','FINALIZADO','NO_SHOW')`,
            [prefix]
        );
        const maxNum = gapRows[0].max_num ?? tckNumber;
        const gap = Math.max(maxNum - tckNumber, 0);
        const limit = await getNoShowRequeueLimit(exec);

        // Tickets that belong to a multi-area visit plan are exempt from the
        // gap limit — the patient being elsewhere in the same visit is
        // expected, not a real no-show.
        if (!belongsToVisitPlan && gap > limit) {
            throw Object.assign(
                new Error(`No se puede reinsertar: ya se llamaron ${gap} turno(s) después (límite: ${limit})`),
                { statusCode: 409 }
            );
        }

        const { rows } = await client.query(
            `UPDATE clinicqueue.tickets
             SET status = 'EN_COLA', station_id = NULL, module_id = NULL,
                 called_at = NULL, called_by = NULL, started_at = NULL, started_by = NULL,
                 ended_at = NULL, ended_by = NULL
             WHERE ticket_id = $1 AND status = 'NO_SHOW'
             RETURNING *`,
            [ticket_id]
        );
        if (!rows.length) throw Object.assign(new Error('El turno cambió de estado, intente de nuevo'), { statusCode: 409 });

        await client.query(
            `INSERT INTO clinicqueue.ticket_events (ticket_id, station_id, event_type, from_status, to_status, details, user_id)
             VALUES ($1, $2, 'TRANSFERRED', 'NO_SHOW', 'EN_COLA', $3, $4)`,
            [ticket_id, station_id, JSON.stringify({ action: 'REQUEUE_NO_SHOW', gap, limit }), user_id]
        );

        return rows[0];
    });
}

module.exports = { createTicket, callNext, startTicket, recallTicket, finishTicket, cancelTicket, noShowTicket, transferTicket, autoNoShow, listNoShowTickets, requeueNoShowTicket, createVisitPlan };
