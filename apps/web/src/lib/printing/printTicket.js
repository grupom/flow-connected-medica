const PRINT_AGENT_URL = 'http://localhost:3000';
const API_BASE = import.meta.env.PUBLIC_API_URL ?? '';

/**
 * Print a ticket via the direct-print-agent.
 * Throws if the agent is unavailable or returns an error.
 *
 * @param {Object} ticketData - { code, prefix, service_name, tck_number }
 */
export async function printTicket(ticketData = null) {
    if (!ticketData?.code) return false;

    const agentAvailable = await checkAgent();
    if (!agentAvailable) {
        throw new Error('El agente de impresión no está disponible en localhost:3000');
    }

    return await printViaAgent(ticketData);
}

async function checkAgent() {
    try {
        const res = await fetch(`${PRINT_AGENT_URL}/api/health`, {
            signal: AbortSignal.timeout(1500)
        });
        return res.ok;
    } catch {
        return false;
    }
}

// ── Settings cache ────────────────────────────────────────────────────────────
// Fetched once per page load; TTL = session lifetime (safe for this use case).

let _settingsCache = null;

async function getTicketSettings() {
    if (_settingsCache) return _settingsCache;
    try {
        const res = await fetch(`${API_BASE}/api/settings`, {
            signal: AbortSignal.timeout(2000)
        });
        if (res.ok) {
            const json = await res.json();
            _settingsCache = json.data || {};
        }
    } catch {
        // Non-critical — defaults will be used
    }
    return _settingsCache || {};
}

/**
 * Formats current date and time as ASCII-safe strings
 * that fit comfortably on a 48-column thermal printer.
 * Example: "23/03/2026  09:41 AM"
 */
function formatDateTime() {
    const pad = n => String(n).padStart(2, '0');
    const d = new Date();
    const fecha = `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`;
    const h = d.getHours();
    const hora = `${pad(h % 12 || 12)}:${pad(d.getMinutes())} ${h >= 12 ? 'PM' : 'AM'}`;
    return `${fecha}  ${hora}`;
}

const BLANK = { kind: 'text', value: '', style: { align: 'center' } };

/**
 * Builds the structured ticket payload for the print agent.
 *
 * Layout (80mm / 48 cols) — double-height, clean (no dividers):
 *
 *            MEDICA               ← ticket_company_name (optional)
 *
 *           FLOW CONNECTED
 *
 *
 *
 *            CONSULTORIO
 *
 *
 *                C03
 *
 *
 *        23/03/2026  09:41 AM
 *
 *
 *      Espere a ser llamado
 *      Please wait to be called
 *
 *
 */
async function buildTicketPayload(ticketData) {
    const settings = await getTicketSettings();

    const companyName = (
        ticketData.company_name ||      // explicit override from caller
        settings.ticket_company_name || // stored setting
        ''
    ).toString().trim().toUpperCase();

    const header = (
        ticketData.service_name ||
        ticketData.serviceName  ||
        ticketData.prefix       ||
        ''
    ).toUpperCase();

    const datetime = formatDateTime();

    const txt = (value, style = {}) => ({ kind: 'text', value, style });

    const items = [
        BLANK,
    ];

    // Company name line — only rendered when configured
    if (companyName) {
        items.push(txt(companyName, { align: 'center', bold: true }));
    }

    items.push(
        txt('FLOW CONNECTED', { align: 'center', bold: true }),
        BLANK,
        BLANK,
        BLANK,

        // ── Service name ──────────────────────────────────────
        txt(header, { align: 'center', bold: true }),
        BLANK,
        BLANK,
        BLANK,

        // ── Ticket code (large) ───────────────────────────────
        txt(ticketData.code, { align: 'center', magnify: 4 }),
        BLANK,
        BLANK,
        BLANK,

        // ── Date / time ───────────────────────────────────────
        txt(datetime, { align: 'center' }),
        BLANK,
        BLANK,
        BLANK,

        // ── Footer ────────────────────────────────────────────
        txt('Espere a ser llamado', { align: 'center' }),
        txt('Please wait to be called', { align: 'center' }),
        BLANK,
        BLANK,
        BLANK,
    );

    return {
        printerId: 'default',
        type: 'ticket',
        content: { width: 48, items }
    };
}

async function printViaAgent(ticketData) {
    const payload = await buildTicketPayload(ticketData);

    const res = await fetch(`${PRINT_AGENT_URL}/api/print/ticket`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
    });

    if (!res.ok) {
        throw new Error(`Print agent responded with ${res.status}`);
    }

    return true;
}
