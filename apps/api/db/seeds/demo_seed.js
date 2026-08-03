'use strict';

require('dotenv').config();

const bcrypt = require('bcrypt');
const { Pool } = require('pg');

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

async function seed() {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');

        console.log('🌱 Seeding demo data...\n');

        // ── Roles ─────────────────────────────────────────────────────────────
        // Normally already seeded by docker/init/01a-reference-data.sql — repeated
        // here (same fixed IDs, ON CONFLICT DO NOTHING) so this script is also
        // self-contained if run against a database where that hasn't happened.
        await client.query(`
      INSERT INTO clinicqueue.roles (role_id, role_code, role_name, description, is_active)
      VALUES
        (1, 'ADMIN',      'Administrador', 'Configura el sistema, catálogos y reportes', true),
        (2, 'DESK',       'Front Desk',    'Crea turnos desde recepción',                true)
      ON CONFLICT (role_id) DO NOTHING
    `);
        console.log('✅ Roles inserted');

        // ── Demo Users ────────────────────────────────────────────────────────
        const adminHash = await bcrypt.hash('admin123!', 12);
        const opHash = await bcrypt.hash('operator1234', 12);

        const { rows: adminRows } = await client.query(`
      INSERT INTO clinicqueue.users (username, email, display_name, password_hash, is_active, status_code)
      VALUES ('admin', 'admin@clinicqueue.local', 'System Admin', $1, true, 'ACTIVE')
      ON CONFLICT (username) DO UPDATE SET password_hash = EXCLUDED.password_hash, status_code = 'ACTIVE'
      RETURNING user_id
    `, [adminHash]);

        const { rows: opRows } = await client.query(`
      INSERT INTO clinicqueue.users (username, email, display_name, password_hash, is_active, status_code)
      VALUES ('operator1', 'op1@clinicqueue.local', 'Operator One', $1, true, 'ACTIVE')
      ON CONFLICT (username) DO UPDATE SET password_hash = EXCLUDED.password_hash, status_code = 'ACTIVE'
      RETURNING user_id
    `, [opHash]);

        console.log('✅ Users inserted');

        // ── Assign roles ──────────────────────────────────────────────────────
        const { rows: roleRows } = await client.query(
            `SELECT role_id, role_code FROM clinicqueue.roles WHERE role_code IN ('ADMIN','DESK')`
        );
        const roleMap = Object.fromEntries(roleRows.map((r) => [r.role_code, r.role_id]));

        if (adminRows[0]) {
            await client.query(`
        INSERT INTO clinicqueue.user_roles (user_id, role_id)
        VALUES ($1, $2) ON CONFLICT DO NOTHING
      `, [adminRows[0].user_id, roleMap.ADMIN]);
        }
        if (opRows[0]) {
            await client.query(`
        INSERT INTO clinicqueue.user_roles (user_id, role_id)
        VALUES ($1, $2) ON CONFLICT DO NOTHING
      `, [opRows[0].user_id, roleMap.DESK]);
        }
        console.log('✅ Role assignments done');

        // ── Demo Queue (module.prefix / station.prefix reference this) ──────────
        await client.query(`
      INSERT INTO clinicqueue.queue_settings (prefix, mode, service_name, icon)
      VALUES ('C', 'DAILY_RESET', 'Consultorio', '🩺')
      ON CONFLICT (prefix) DO NOTHING
    `);
        console.log('✅ Queue setting inserted');

        // ── Demo Module ───────────────────────────────────────────────────────
        const { rows: modRows } = await client.query(`
      INSERT INTO clinicqueue.modules (module_code, module_name, prefix, is_active)
      VALUES ('C01', 'Consultorio 1', 'C', true)
      ON CONFLICT (module_code) DO NOTHING
      RETURNING module_id
    `);
        const moduleId = modRows[0]?.module_id;
        console.log('✅ Module inserted');

        // ── Demo Stations ─────────────────────────────────────────────────────
        const { rows: staRows } = await client.query(`
      INSERT INTO clinicqueue.stations (station_code, station_name, prefix, module_id, is_active)
      VALUES
        ('S01', 'Station 01', 'C', $1, true),
        ('S02', 'Station 02', 'C', $1, true),
        ('S03', 'Station 03', 'C', $1, true)
      ON CONFLICT (station_code) DO NOTHING
      RETURNING station_id, station_code
    `, [moduleId]);
        console.log('✅ Stations inserted');

        // ── Demo Display Board ────────────────────────────────────────────────
        const { rows: boardRows } = await client.query(`
      INSERT INTO clinicqueue.display_boards (board_code, board_name, is_active, sound_enabled, show_waiting_count, max_in_service_rows)
      VALUES ('DEMO', 'Main Display Board', true, true, true, 8)
      ON CONFLICT (board_code) DO NOTHING
      RETURNING board_id
    `);
        const boardId = boardRows[0]?.board_id;

        if (boardId && staRows.length) {
            for (let i = 0; i < staRows.length; i++) {
                await client.query(`
          INSERT INTO clinicqueue.board_stations (board_id, station_id, display_order, is_enabled)
          VALUES ($1, $2, $3, true)
          ON CONFLICT (board_id, station_id) DO NOTHING
        `, [boardId, staRows[i].station_id, i + 1]);
            }
            console.log('✅ Board stations linked');
        }

        await client.query('COMMIT');
        console.log('\n🎉 Seed complete!\n');
        console.log('  Admin login:    admin / admin123!');
        console.log('  Operator login: operator1 / operator1234\n');
    } catch (err) {
        await client.query('ROLLBACK');
        console.error('❌ Seed failed:', err.message);
        process.exit(1);
    } finally {
        client.release();
        await pool.end();
    }
}

seed();
