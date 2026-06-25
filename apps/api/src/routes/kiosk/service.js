'use strict';

const { query } = require('../../db/pool');

/**
 * Retrieves the kiosk session data including authorized queues based on the JWT user_id.
 */
async function getKioskSession(userId) {
    // Determine the Kiosk bound to this authenticated user
    const { rows: kioskRows } = await query(
        `SELECT k.kiosk_id, k.kiosk_code, k.kiosk_name, k.location_desc
         FROM clinicqueue.kiosks k 
         WHERE k.user_id = $1 AND k.is_active = true
         LIMIT 1`,
        [userId]
    );

    if (!kioskRows.length) return null;
    const kiosk = kioskRows[0];

    // Read the completely updated allowed queues from the view v_kiosk_allowed_queues
    const { rows: allowedQueues } = await query(
        `SELECT v.prefix, v.service_name, v.icon, v.mode, v.allow_walkins, v.sound_enabled
         FROM clinicqueue.v_kiosk_allowed_queues v
         WHERE v.kiosk_id = $1
         ORDER BY v.service_name ASC`,
        [kiosk.kiosk_id]
    );

    return {
        kiosk,
        allowedQueues
    };
}

/**
 * Securely issue a ticket validating if the underlying kiosk_id is permitted for the requested prefix.
 */
async function issueKioskTicket(userId, prefix) {
    prefix = prefix.toUpperCase().trim();

    // 1. Authenticate that this user_id maps to an active kiosk
    const session = await getKioskSession(userId);
    if (!session) {
        const err = new Error('User is not linked to any active Kiosk');
        err.statusCode = 403;
        throw err;
    }

    const { kiosk, allowedQueues } = session;

    // 2. Validate prefix authorization using the DB view results
    const isAuthorized = allowedQueues.some(q => q.prefix === prefix);
    if (!isAuthorized) {
        const err = new Error(`Kiosk [${kiosk.kiosk_name}] is not authorized to issue tickets for prefix [${prefix}]`);
        err.statusCode = 403;
        throw err;
    }

    // 3. Ensure walk-ins are allowed globally for this prefix
    const queueConfig = allowedQueues.find(q => q.prefix === prefix);
    if (!queueConfig.allow_walkins) {
        const err = new Error(`Queue [${prefix}] is not currently accepting Kiosk walk-ins`);
        err.statusCode = 403;
        throw err;
    }

    // 4. Issue the ticket using DB function
    const { rows } = await query(
        `SELECT * FROM clinicqueue.create_ticket($1, $2, $3)`,
        [prefix, userId, true] // true means is_walkin = true
    );
    
    const dbResult = rows[0];
    if (!dbResult) throw new Error('Failed to create ticket in database');
    
    const ticketId = dbResult.out_ticket_id || dbResult.ticket_id;
    
    // 5. Update the ticket to track Kiosk metadata
    const { rows: updatedRows } = await query(
        `UPDATE clinicqueue.tickets 
         SET issue_channel = 'KIOSK', 
             issued_by_kiosk_id = $2
         WHERE ticket_id = $1
         RETURNING *`,
        [ticketId, kiosk.kiosk_id]
    );

    const ticket = updatedRows[0];
    
    return ticket;
}

module.exports = {
    getKioskSession,
    issueKioskTicket
};
