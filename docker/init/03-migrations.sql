-- ──────────────────────────────────────────────────────────────────────────────
-- 03-migrations.sql
-- Schema updates applied after the base DDL dump (clinicqueue-DDL.sql).
-- All statements are idempotent (IF NOT EXISTS / CREATE OR REPLACE).
-- ──────────────────────────────────────────────────────────────────────────────

-- ── 1. display_boards — additional columns ────────────────────────────────────

ALTER TABLE clinicqueue.display_boards
    ADD COLUMN IF NOT EXISTS description        TEXT          NULL,
    ADD COLUMN IF NOT EXISTS sound_enabled      BOOLEAN       NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS show_waiting_count BOOLEAN       NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS max_in_service_rows INTEGER      NOT NULL DEFAULT 10,
    ADD COLUMN IF NOT EXISTS voice_speed        NUMERIC(3,2)  NOT NULL DEFAULT 1.0,
    ADD COLUMN IF NOT EXISTS language           VARCHAR(10)   NOT NULL DEFAULT 'es',
    ADD COLUMN IF NOT EXISTS ding_sound         VARCHAR(20)   NOT NULL DEFAULT 'gentle',
    ADD COLUMN IF NOT EXISTS updated_at         TIMESTAMPTZ   NOT NULL DEFAULT now();

-- ── 2. system_settings — key/value store ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS clinicqueue.system_settings (
    key        VARCHAR(100) PRIMARY KEY,
    value      JSONB        NOT NULL,
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

INSERT INTO clinicqueue.system_settings (key, value)
VALUES ('multi_language', 'false')
ON CONFLICT (key) DO NOTHING;

-- ── 3. queue_settings — archived flag and priority queues ─────────────────────

ALTER TABLE clinicqueue.queue_settings
    ADD COLUMN IF NOT EXISTS archived       BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS is_priority_for TEXT    NULL
        REFERENCES clinicqueue.queue_settings(prefix)
        ON UPDATE CASCADE ON DELETE SET NULL;

-- ── 4. Fix unique index on tickets to include ticket_date ─────────────────────
-- Old index blocked creating ticket C01 today if C01 from yesterday was still open.

DROP INDEX IF EXISTS clinicqueue.ux_tickets_active_prefix_number;

CREATE UNIQUE INDEX IF NOT EXISTS ux_tickets_active_prefix_number
    ON clinicqueue.tickets (prefix, tck_number, ticket_date)
    WHERE status = ANY (ARRAY[
        'EN_COLA'::clinicqueue.ticket_status,
        'LLAMADO'::clinicqueue.ticket_status,
        'EN_ATENCION'::clinicqueue.ticket_status
    ]);

-- ── 5. v_kiosk_allowed_queues — exclude archived queues ──────────────────────

CREATE OR REPLACE VIEW clinicqueue.v_kiosk_allowed_queues AS
SELECT
    k.kiosk_id,
    k.kiosk_code,
    k.kiosk_name,
    k.user_id,
    k.location_desc,
    k.is_active      AS kiosk_is_active,
    kq.kiosk_queue_id,
    kq.prefix,
    q.service_name,
    q.icon,
    q.mode,
    q.allow_walkins,
    q.sound_enabled,
    kq.is_enabled
FROM clinicqueue.kiosks k
JOIN clinicqueue.kiosk_queues kq ON kq.kiosk_id = k.kiosk_id
JOIN clinicqueue.queue_settings q  ON q.prefix   = kq.prefix
WHERE k.is_active   = true
  AND kq.is_enabled = true
  AND q.archived    = false;

-- ── 6. trg_modules_normalize — support multi-char prefixes (e.g. CF, PD) ──────

CREATE OR REPLACE FUNCTION clinicqueue.trg_modules_normalize()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.prefix      := upper(trim(NEW.prefix));
    NEW.module_code := upper(trim(NEW.module_code));
    NEW.updated_at  := now();

    IF left(NEW.module_code, length(NEW.prefix)) <> NEW.prefix THEN
        RAISE EXCEPTION
            'El module_code (%) no coincide con el prefix (%)',
            NEW.module_code, NEW.prefix;
    END IF;

    RETURN NEW;
END;
$$;

-- ── 7. call_next_ticket — priority queue support ─────────────────────────────

CREATE OR REPLACE FUNCTION clinicqueue.call_next_ticket(
    p_station_id bigint,
    p_user_id    bigint
)
RETURNS TABLE(
    out_ticket_id  bigint,
    out_code       text,
    out_prefix     text,
    out_tck_number integer,
    out_module_id  bigint,
    out_station_id bigint,
    out_status     clinicqueue.ticket_status,
    out_called_at  timestamp with time zone
)
LANGUAGE plpgsql AS $$
DECLARE
    v_prefix    text;
    v_module_id bigint;
    v_now       timestamptz := now();
BEGIN
    SELECT s.prefix, s.module_id
    INTO v_prefix, v_module_id
    FROM clinicqueue.stations s
    WHERE s.station_id = p_station_id AND s.is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Station % no existe o está inactiva', p_station_id;
    END IF;

    PERFORM 1 FROM clinicqueue.users u
    WHERE u.user_id = p_user_id AND u.is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % no existe o está inactivo', p_user_id;
    END IF;

    PERFORM 1 FROM clinicqueue.station_users su
    WHERE su.station_id = p_station_id
      AND su.user_id    = p_user_id
      AND su.is_enabled = true
      AND (su.valid_from IS NULL OR su.valid_from <= v_now)
      AND (su.valid_to   IS NULL OR su.valid_to   >  v_now);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % no está autorizado para operar Station %',
            p_user_id, p_station_id;
    END IF;

    PERFORM 1 FROM clinicqueue.tickets t
    WHERE t.station_id = p_station_id AND t.status = 'LLAMADO';

    IF FOUND THEN
        RAISE EXCEPTION
            'Station % ya tiene un ticket en estado LLAMADO. '
            'Debe iniciar/finalizar/no-show antes de llamar otro.',
            p_station_id;
    END IF;

    WITH next_ticket AS (
        SELECT t.ticket_id
        FROM   clinicqueue.tickets t
        JOIN   clinicqueue.queue_settings qs ON qs.prefix = t.prefix
        WHERE  (t.prefix = v_prefix OR qs.is_priority_for = v_prefix)
          AND  t.status     = 'EN_COLA'
          AND  t.module_id IS NULL
        ORDER BY
            CASE WHEN qs.is_priority_for IS NOT NULL THEN 0 ELSE 1 END ASC,
            t.created_at ASC,
            t.ticket_id  ASC
        FOR UPDATE SKIP LOCKED
        LIMIT 1
    )
    UPDATE clinicqueue.tickets t
    SET    status     = 'LLAMADO',
           called_at  = v_now,
           station_id = p_station_id,
           module_id  = v_module_id,
           called_by  = p_user_id
    FROM   next_ticket nt
    WHERE  t.ticket_id = nt.ticket_id
    RETURNING
        t.ticket_id, t.code, t.prefix, t.tck_number,
        t.module_id, t.station_id, t.status, t.called_at
    INTO
        out_ticket_id, out_code, out_prefix, out_tck_number,
        out_module_id, out_station_id, out_status, out_called_at;

    IF out_ticket_id IS NULL THEN
        RETURN;
    END IF;

    INSERT INTO clinicqueue.ticket_events(
        ticket_id, event_type, from_status, to_status,
        station_id, module_id, user_id, event_at, details
    ) VALUES (
        out_ticket_id, 'CALLED', 'EN_COLA', 'LLAMADO',
        out_station_id, out_module_id, p_user_id, v_now,
        jsonb_build_object('station_id', out_station_id, 'module_id', out_module_id)
    );

    RETURN NEXT;
END;
$$;

-- ── 8. create_ticket — block walkin on priority prefix ────────────────────────

CREATE OR REPLACE FUNCTION clinicqueue.create_ticket(
    p_prefix     text,
    p_created_by bigint  DEFAULT NULL,
    p_is_walkin  boolean DEFAULT true
)
RETURNS TABLE(
    out_ticket_id  bigint,
    out_prefix     text,
    out_tck_number integer,
    out_code       text,
    out_status     clinicqueue.ticket_status
)
LANGUAGE plpgsql AS $$
DECLARE
    v_prefix          text    := upper(trim(p_prefix::text));
    v_mode            text;
    v_min             int;
    v_max             int;
    v_key             text;
    v_last            int;
    v_try             int     := 0;
    v_candidate       int;
    v_max_active      int;
    v_allow_walkins   boolean;
    v_is_priority_for text;
    v_active_count    int;
BEGIN
    SELECT qs.mode, qs.min_number, qs.max_number,
           qs.max_active, qs.allow_walkins, qs.is_priority_for
    INTO   v_mode, v_min, v_max,
           v_max_active, v_allow_walkins, v_is_priority_for
    FROM   clinicqueue.queue_settings qs
    WHERE  qs.prefix = v_prefix;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Prefijo % no existe en clinicqueue.queue_settings', v_prefix;
    END IF;

    IF v_is_priority_for IS NOT NULL AND p_is_walkin THEN
        RAISE EXCEPTION
            'La cola % es de prioridad exclusiva. '
            'Los turnos de prioridad solo pueden generarse desde Recepción.',
            v_prefix;
    END IF;

    IF p_is_walkin AND NOT v_allow_walkins THEN
        RAISE EXCEPTION 'La cola % no permite walk-ins (solo con cita/check-in)', v_prefix;
    END IF;

    IF v_max_active IS NOT NULL THEN
        SELECT count(*) INTO v_active_count
        FROM   clinicqueue.tickets t
        WHERE  t.prefix = v_prefix
          AND  t.status IN ('EN_COLA','LLAMADO','EN_ATENCION');

        IF v_active_count >= v_max_active THEN
            RAISE EXCEPTION 'Cola % llena. Activos: %, Max: %',
                v_prefix, v_active_count, v_max_active;
        END IF;
    END IF;

    v_key := CASE WHEN v_mode = 'DAILY_RESET'
                  THEN to_char(current_date, 'YYYY-MM-DD')
                  ELSE 'GLOBAL' END;

    INSERT INTO clinicqueue.queue_counters(prefix, counter_key, last_number)
    VALUES (v_prefix, v_key, 0)
    ON CONFLICT (prefix, counter_key) DO NOTHING;

    SELECT qc.last_number INTO v_last
    FROM   clinicqueue.queue_counters qc
    WHERE  qc.prefix = v_prefix AND qc.counter_key = v_key
    FOR UPDATE;

    WHILE v_try < (v_max - v_min + 1) LOOP
        v_try := v_try + 1;

        v_candidate := CASE
            WHEN v_last < v_min OR v_last > v_max THEN v_min
            WHEN v_last + 1 > v_max               THEN v_min
            ELSE v_last + 1
        END;

        BEGIN
            INSERT INTO clinicqueue.tickets(prefix, tck_number, code, status, created_by)
            VALUES (v_prefix, v_candidate,
                    v_prefix || lpad(v_candidate::text, 2, '0'),
                    'EN_COLA', p_created_by)
            RETURNING ticket_id, prefix, tck_number, code, status
            INTO out_ticket_id, out_prefix, out_tck_number, out_code, out_status;

            UPDATE clinicqueue.queue_counters
            SET    last_number = v_candidate, updated_at = now()
            WHERE  prefix = v_prefix AND counter_key = v_key;

            INSERT INTO clinicqueue.ticket_events(ticket_id, event_type, from_status, to_status, user_id)
            VALUES (out_ticket_id, 'CREATED', NULL, 'EN_COLA', p_created_by);

            RETURN NEXT;
            RETURN;

        EXCEPTION
            WHEN unique_violation THEN
                v_last := v_candidate;
                CONTINUE;
        END;
    END LOOP;

    RAISE EXCEPTION 'Cola % llena: no hay números libres %-%', v_prefix, v_min, v_max;
END;
$$;
