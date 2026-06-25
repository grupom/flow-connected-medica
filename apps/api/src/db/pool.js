'use strict';

const { Pool } = require('pg');
const env = require('../config/env');

const pool = new Pool({
    connectionString: env.DATABASE_URL,
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
});

pool.on('error', (err) => {
    console.error('[DB] Unexpected error on idle client', err);
});

/**
 * Run a parameterised query and return the result.
 * @param {string} text  SQL string with $1, $2 … placeholders
 * @param {Array}  [params]  Query parameters
 */
async function query(text, params) {
    const client = await pool.connect();
    try {
        return await client.query(text, params);
    } finally {
        client.release();
    }
}

/**
 * Run multiple statements inside a single transaction.
 * @param {function(import('pg').PoolClient): Promise<any>} callback
 */
async function transaction(callback) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const result = await callback(client);
        await client.query('COMMIT');
        return result;
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

module.exports = { pool, query, transaction };
