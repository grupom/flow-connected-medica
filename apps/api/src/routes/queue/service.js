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
    const { rows } = await query(
        `UPDATE clinicqueue.tickets
     SET status = 'EN_ATENCION', started_at = now(), started_by = $2
     WHERE ticket_id = $1 AND status = 'LLAMADO'
     RETURNING *`,
        [ticket_id, user_id]
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
    const { rows } = await query(
        `UPDATE clinicqueue.tickets SET called_at = now() WHERE ticket_id = $1 AND status = 'LLAMADO' RETURNING *`,
        [ticket_id]
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
    const { rows } = await query(
        `UPDATE clinicqueue.tickets
     SET status = 'FINALIZADO', ended_at = now(), ended_by = $2
     WHERE ticket_id = $1 AND status = 'EN_ATENCION'
     RETURNING *`,
        [ticket_id, user_id]
    );
    if (!rows.length) throw Object.assign(new Error('Ticket not in EN_ATENCION state'), { statusCode: 409 });
    await query(
        `INSERT INTO clinicqueue.ticket_events (ticket_id, station_id, event_type, from_status, to_status, details, user_id) VALUES ($1, $2, 'FINISHED', 'EN_ATENCION', 'FINALIZADO', $3, $4)`,
        [ticket_id, station_id, notes ? JSON.stringify({ notes }) : null, user_id]
    );
    return rows[0];
}

/**
 * Cancel a ticket.
 */
async function cancelTicket({ ticket_id, user_id, reason }) {
    // get old status
    const { rows: tRows } = await query(`SELECT status FROM clinicqueue.tickets WHERE ticket_id = $1`, [ticket_id]);
    if (!tRows.length) throw Object.assign(new Error('Ticket not found'), { statusCode: 404 });
    const fromStatus = tRows[0].status;

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
    const { rows } = await query(
        `UPDATE clinicqueue.tickets
     SET status = 'NO_SHOW'
     WHERE ticket_id = $1 AND status = 'LLAMADO'
     RETURNING *`,
        [ticket_id]
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
        // 1. Get current ticket
        const { rows: tRows } = await client.query(
            `SELECT * FROM clinicqueue.tickets WHERE ticket_id = $1 FOR UPDATE`,
            [ticket_id]
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

module.exports = { createTicket, callNext, startTicket, recallTicket, finishTicket, cancelTicket, noShowTicket, transferTicket, autoNoShow };
