'use strict';

const { query } = require('../../../db/pool');

module.exports = async function adminKiosksRoutes(fastify) {
    // GET /api/admin/kiosks
    // List all kiosks
    fastify.get('/', fastify.adminOnly, async (request, reply) => {
        const { rows } = await query(
            `SELECT k.*, u.username as linked_user
             FROM clinicqueue.kiosks k
             LEFT JOIN clinicqueue.users u ON k.user_id = u.user_id
             ORDER BY k.kiosk_name ASC`,
            []
        );
        return reply.send({ data: rows });
    });

    // GET /api/admin/kiosks/:id
    // Get a specific kiosk and its allowed queues
    fastify.get('/:id', {
        ...fastify.adminOnly,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } }
        }
    }, async (request, reply) => {
        const { id } = request.params;
        
        // 1. Get Kiosk
        const { rows: kioskRows } = await query(
            `SELECT * FROM clinicqueue.kiosks WHERE kiosk_id = $1`,
            [id]
        );
        
        if (!kioskRows.length) {
            return reply.code(404).send({ error: 'Not Found', message: 'Kiosk not found' });
        }
        
        // 2. Get allowed queues
        const { rows: queueRows } = await query(
            `SELECT prefix, is_enabled 
             FROM clinicqueue.kiosk_queues 
             WHERE kiosk_id = $1`,
            [id]
        );

        return reply.send({ 
            data: {
                kiosk: kioskRows[0],
                queues: queueRows
            } 
        });
    });

    // POST /api/admin/kiosks
    // Create a new kiosk
    fastify.post('/', {
        ...fastify.adminOnly,
        schema: {
            body: {
                type: 'object',
                required: ['kiosk_name', 'user_id', 'kiosk_code'],
                properties: {
                    kiosk_code: { type: 'string' },
                    kiosk_name: { type: 'string' },
                    user_id: { type: 'integer' },
                    location_desc: { type: 'string' }
                }
            }
        }
    }, async (request, reply) => {
        const { kiosk_code, kiosk_name, user_id, location_desc } = request.body;
        const created_by = request.user.user_id;

        try {
            const { rows } = await query(
                `INSERT INTO clinicqueue.kiosks (kiosk_code, kiosk_name, user_id, location_desc, created_by)
                 VALUES ($1, $2, $3, $4, $5)
                 RETURNING *`,
                [kiosk_code.toUpperCase(), kiosk_name, user_id, location_desc || null, created_by]
            );
            return reply.code(201).send({ data: rows[0] });
        } catch (error) {
            // Handle unique constraint violations
            if (error.code === '23505') {
                return reply.code(409).send({ error: 'Conflict', message: 'Kiosk code or User already assigned to another kiosk' });
            }
            throw error;
        }
    });

    // PUT /api/admin/kiosks/:id
    // Update an existing kiosk
    fastify.put('/:id', {
        ...fastify.adminOnly,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: {
                type: 'object',
                properties: {
                    kiosk_name: { type: 'string' },
                    user_id: { type: 'integer' },
                    location_desc: { type: 'string' }
                }
            }
        }
    }, async (request, reply) => {
        const { id } = request.params;
        const { kiosk_name, user_id, location_desc } = request.body;
        const updated_by = request.user.user_id;

        const { rows } = await query(
            `UPDATE clinicqueue.kiosks
             SET kiosk_name = COALESCE($2, kiosk_name),
                 user_id = COALESCE($3, user_id),
                 location_desc = $4,
                 updated_by = $5,
                 updated_at = now()
             WHERE kiosk_id = $1
             RETURNING *`,
            [id, kiosk_name || null, user_id || null, location_desc || null, updated_by]
        );

        if (!rows.length) {
            return reply.code(404).send({ error: 'Not Found', message: 'Kiosk not found' });
        }
        return reply.send({ data: rows[0] });
    });

    // PATCH /api/admin/kiosks/:id/status
    // Update kiosk active status
    fastify.patch('/:id/status', {
        ...fastify.adminOnly,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: { type: 'object', required: ['is_active'], properties: { is_active: { type: 'boolean' } } }
        }
    }, async (request, reply) => {
        const { id } = request.params;
        const updated_by = request.user.user_id;
        
        const { rows } = await query(
            `UPDATE clinicqueue.kiosks 
             SET is_active = $2, updated_by = $3, updated_at = now() 
             WHERE kiosk_id = $1 
             RETURNING *`,
            [id, request.body.is_active, updated_by]
        );
        
        if (!rows.length) return reply.code(404).send({ error: 'Not Found', message: 'Kiosk not found' });
        return reply.send({ data: rows[0] });
    });

    // PUT /api/admin/kiosks/:id/queues
    // Update allowed queues for a kiosk
    fastify.put('/:id/queues', {
        ...fastify.adminOnly,
        schema: {
            params: { type: 'object', properties: { id: { type: 'integer' } } },
            body: {
                type: 'object',
                required: ['queues'],
                properties: {
                    queues: {
                        type: 'array',
                        items: { type: 'string' } // Array of prefixes ['C', 'E']
                    }
                }
            }
        }
    }, async (request, reply) => {
        const { id } = request.params;
        const { queues } = request.body;
        const created_by = request.user.user_id;

        // Start transaction
        const client = await require('../../../db/pool').pool.connect();
        try {
            await client.query('BEGIN');

            // 1. Verify kiosk exists
            const { rows: kRows } = await client.query('SELECT kiosk_id FROM clinicqueue.kiosks WHERE kiosk_id = $1', [id]);
            if (!kRows.length) {
                throw { statusCode: 404, message: 'Kiosk not found' };
            }

            // 2. Remove existing queue associations
            await client.query('DELETE FROM clinicqueue.kiosk_queues WHERE kiosk_id = $1', [id]);

            // 3. Insert new queue associations
            if (queues && queues.length > 0) {
                // Prepare values for bulk insert
                const values = queues.map((prefix, index) => {
                    return `($1, $${index + 2}, true, $${queues.length + 2})`;
                }).join(', ');
                
                const params = [id, ...queues.map(q => q.toUpperCase()), created_by];
                
                await client.query(
                    `INSERT INTO clinicqueue.kiosk_queues (kiosk_id, prefix, is_enabled, created_by)
                     VALUES ${values}`,
                    params
                );
            }

            await client.query('COMMIT');
            
            // Return updated list
            const { rows: updatedRows } = await query(
                `SELECT prefix, is_enabled FROM clinicqueue.kiosk_queues WHERE kiosk_id = $1`,
                [id]
            );
            
            return reply.send({ data: updatedRows });

        } catch (error) {
            await client.query('ROLLBACK');
            if (error.statusCode) {
                return reply.code(error.statusCode).send({ error: 'Error', message: error.message });
            }
            throw error;
        } finally {
            client.release();
        }
    });
};
