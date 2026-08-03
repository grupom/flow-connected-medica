-- ──────────────────────────────────────────────────────────────────────────────
-- 01a-reference-data.sql
-- Fixed lookup/reference rows required for the schema's foreign keys to work
-- at all (e.g. clinicqueue.users.status_code -> user_statuses). Not
-- client-specific data — every install needs these same rows. Runs after
-- 01-schema.sql creates the tables. Idempotent (ON CONFLICT DO NOTHING).
-- ──────────────────────────────────────────────────────────────────────────────

INSERT INTO clinicqueue.user_statuses (status_code, status_name, is_login_allowed, sort_order, is_system) VALUES
    ('ACTIVE',   'Active',   true,  1, true),
    ('INACTIVE', 'Inactive', false, 2, true),
    ('ARCHIVED', 'Archived', false, 3, true)
ON CONFLICT (status_code) DO NOTHING;

INSERT INTO clinicqueue.roles (role_id, role_code, role_name, description, is_active) VALUES
    (1, 'ADMIN',      'Administrador',      'Configura el sistema, catálogos y reportes',                      true),
    (2, 'DESK',       'Front Desk',         'Crea turnos desde recepción',                                     true),
    (3, 'STATION',    'Estación',           'Opera una estación Doctor/Analista que atiende turnos (trazabilidad)', true),
    (4, 'KIOSK',      'Kiosk Station',      'Usuario autenticado para estación de autogestión',                true),
    (5, 'SUPERVISOR', 'Supervisor',         'Puede reasignar estaciones',                                      true)
ON CONFLICT (role_id) DO NOTHING;

-- Keep the roles sequence ahead of the fixed IDs above, so future INSERTs
-- without an explicit role_id (e.g. from the admin UI) don't collide with them.
SELECT setval(pg_get_serial_sequence('clinicqueue.roles', 'role_id'), (SELECT MAX(role_id) FROM clinicqueue.roles));
