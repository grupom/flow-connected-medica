'use strict';

const dailyCloseBodySchema = {
    type: 'object',
    required: ['operational_date'],
    properties: {
        operational_date: {
            type: 'string',
            format: 'date',
            description: 'The operational date up to which to evaluate pending tickets (format: YYYY-MM-DD)'
        }
    }
};

const dailyCloseResponseSchema = {
    type: 'object',
    properties: {
        data: {
            type: 'array',
            items: {
                type: 'object',
                properties: {
                    out_run_id: { type: ['integer', 'null'] },
                    out_ticket_id: { type: 'integer' },
                    out_code: { type: 'string' },
                    out_prefix: { type: 'string' },
                    out_old_status: { type: 'string' },
                    out_new_status: { type: 'string' },
                    out_ticket_date: { type: 'string', format: 'date' },
                    out_closed_at: { type: ['string', 'null'], format: 'date-time' }
                }
            }
        }
    }
};

exports.previewSchema = {
    body: dailyCloseBodySchema,
    response: { 200: dailyCloseResponseSchema }
};

exports.runSchema = {
    body: dailyCloseBodySchema,
    response: { 200: dailyCloseResponseSchema }
};
