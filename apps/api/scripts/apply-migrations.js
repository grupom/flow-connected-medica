'use strict';

// Tracked migration runner. Applies the SQL files that make up the schema on
// top of the base dump (clinicqueue-DDL.sql, mounted as 01-schema.sql), in
// the same order docker-compose mounts them as postgres init scripts —
// recording each one in clinicqueue.schema_migrations so re-running this is a
// no-op for anything already applied. Every migration file is idempotent
// (IF NOT EXISTS / CREATE OR REPLACE), so applying an already-migrated
// database is safe.
//
// Usage: npm run migrate   (from apps/api)
//
// Adding a new migration: drop a new docker/init/NN-*.sql file, add its mount
// to docker-compose.yml (next NN), and append an entry below with a matching
// version name.

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const MIGRATIONS = [
    { version: '01a_reference_data', file: path.join(__dirname, '../../../docker/init/01a-reference-data.sql') },
    { version: '001_refresh_tokens', file: path.join(__dirname, '../db/migrations/001_refresh_tokens.sql') },
    { version: '03_migrations',      file: path.join(__dirname, '../../../docker/init/03-migrations.sql') },
    { version: '04_ad_campaigns',    file: path.join(__dirname, '../../../docker/init/04-ad-campaigns.sql') },
    { version: '05_visit_plans',     file: path.join(__dirname, '../../../docker/init/05-visit-plans.sql') },
];

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

async function run() {
    const client = await pool.connect();
    try {
        await client.query(`
            CREATE TABLE IF NOT EXISTS clinicqueue.schema_migrations (
                version    TEXT PRIMARY KEY,
                applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
            )
        `);

        const { rows } = await client.query('SELECT version FROM clinicqueue.schema_migrations');
        const applied = new Set(rows.map((r) => r.version));

        for (const { version, file } of MIGRATIONS) {
            if (applied.has(version)) {
                console.log(`⏭️  ${version} — already applied, skipping`);
                continue;
            }

            const sql = fs.readFileSync(file, 'utf8');
            console.log(`▶️  ${version} — applying ${path.basename(file)}...`);

            await client.query('BEGIN');
            try {
                await client.query(sql);
                await client.query(
                    'INSERT INTO clinicqueue.schema_migrations (version) VALUES ($1)',
                    [version]
                );
                await client.query('COMMIT');
                console.log(`✅  ${version} — applied and recorded`);
            } catch (err) {
                await client.query('ROLLBACK');
                throw new Error(`Migration ${version} failed, rolled back: ${err.message}`);
            }
        }

        console.log('\n🎉  Database is up to date.');
    } finally {
        client.release();
        await pool.end();
    }
}

run().catch((err) => {
    console.error('❌', err.message);
    process.exit(1);
});
