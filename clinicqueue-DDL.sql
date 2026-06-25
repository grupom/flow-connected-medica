--
-- PostgreSQL database dump
--

-- Dumped from database version 15.8
-- Dumped by pg_dump version 16.4

-- Started on 2026-03-09 16:59:31

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 13 (class 2615 OID 55196)
-- Name: clinicqueue; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA clinicqueue;


ALTER SCHEMA clinicqueue OWNER TO postgres;

--
-- TOC entry 1752 (class 1247 OID 55439)
-- Name: ticket_event_type; Type: TYPE; Schema: clinicqueue; Owner: postgres
--

CREATE TYPE clinicqueue.ticket_event_type AS ENUM (
    'CREATED',
    'CALLED',
    'STARTED',
    'FINISHED',
    'RECALLED',
    'NO_SHOW',
    'CANCELLED',
    'TRANSFERRED',
    'NOTE_ADDED',
    'AUTO_CLOSED'
);


ALTER TYPE clinicqueue.ticket_event_type OWNER TO postgres;

--
-- TOC entry 1746 (class 1247 OID 55370)
-- Name: ticket_status; Type: TYPE; Schema: clinicqueue; Owner: postgres
--

CREATE TYPE clinicqueue.ticket_status AS ENUM (
    'EN_COLA',
    'LLAMADO',
    'EN_ATENCION',
    'FINALIZADO',
    'NO_SHOW',
    'CANCELADO',
    'TRANSFERIDO',
    'EXPIRADO'
);


ALTER TYPE clinicqueue.ticket_status OWNER TO postgres;

--
-- TOC entry 721 (class 1255 OID 55665)
-- Name: add_station_to_board(bigint, bigint, integer, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.add_station_to_board(p_board_id bigint, p_station_id bigint, p_display_order integer DEFAULT 1, p_is_enabled boolean DEFAULT true) RETURNS TABLE(out_board_id bigint, out_station_id bigint, out_display_order integer, out_is_enabled boolean, out_created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF p_display_order IS NULL OR p_display_order < 1 THEN
    RAISE EXCEPTION 'display_order debe ser >= 1';
  END IF;

  -- validar board
  PERFORM 1 FROM clinicqueue.display_boards b WHERE b.board_id = p_board_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Board % no existe', p_board_id;
  END IF;

  -- validar station
  PERFORM 1 FROM clinicqueue.stations s WHERE s.station_id = p_station_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Station % no existe', p_station_id;
  END IF;

  INSERT INTO clinicqueue.board_stations(board_id, station_id, display_order, is_enabled)
  VALUES (p_board_id, p_station_id, p_display_order, COALESCE(p_is_enabled, true))
  ON CONFLICT (board_id, station_id) DO UPDATE
    SET display_order = EXCLUDED.display_order,
        is_enabled    = EXCLUDED.is_enabled
  RETURNING board_id, station_id, display_order, is_enabled, created_at
  INTO out_board_id, out_station_id, out_display_order, out_is_enabled, out_created_at;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.add_station_to_board(p_board_id bigint, p_station_id bigint, p_display_order integer, p_is_enabled boolean) OWNER TO postgres;

--
-- TOC entry 697 (class 1255 OID 55629)
-- Name: assign_role_to_user(bigint, bigint, bigint); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.assign_role_to_user(p_user_id bigint, p_role_id bigint, p_assigned_by bigint DEFAULT NULL::bigint) RETURNS TABLE(out_user_id bigint, out_role_id bigint, out_assigned_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- user activo
  PERFORM 1 FROM clinicqueue.users u WHERE u.user_id=p_user_id AND u.is_active=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'User % no existe o está inactivo', p_user_id; END IF;

  -- rol activo
  PERFORM 1 FROM clinicqueue.roles r WHERE r.role_id=p_role_id AND r.is_active=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Role % no existe o está inactivo', p_role_id; END IF;

  -- assigned_by opcional
  IF p_assigned_by IS NOT NULL THEN
    PERFORM 1 FROM clinicqueue.users u WHERE u.user_id=p_assigned_by AND u.is_active=true;
    IF NOT FOUND THEN RAISE EXCEPTION 'assigned_by % no existe o está inactivo', p_assigned_by; END IF;
  END IF;

  INSERT INTO clinicqueue.user_roles(user_id, role_id, assigned_by)
  VALUES (p_user_id, p_role_id, p_assigned_by)
  ON CONFLICT (user_id, role_id) DO UPDATE
    SET assigned_by = EXCLUDED.assigned_by,
        assigned_at = now()
  RETURNING user_id, role_id, assigned_at
  INTO out_user_id, out_role_id, out_assigned_at;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.assign_role_to_user(p_user_id bigint, p_role_id bigint, p_assigned_by bigint) OWNER TO postgres;

--
-- TOC entry 705 (class 1255 OID 55637)
-- Name: assign_user_to_station(bigint, bigint, bigint, timestamp with time zone, timestamp with time zone, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.assign_user_to_station(p_station_id bigint, p_user_id bigint, p_assigned_by bigint DEFAULT NULL::bigint, p_valid_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_valid_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_is_enabled boolean DEFAULT true) RETURNS TABLE(out_station_id bigint, out_user_id bigint, out_is_enabled boolean, out_valid_from timestamp with time zone, out_valid_to timestamp with time zone, out_assigned_at timestamp with time zone, out_assigned_by bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Validar estación
  PERFORM 1 FROM clinicqueue.stations s WHERE s.station_id=p_station_id AND s.is_active=true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Station % no existe o está inactiva', p_station_id;
  END IF;

  -- Validar usuario
  PERFORM 1 FROM clinicqueue.users u WHERE u.user_id=p_user_id AND u.is_active=true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % no existe o está inactivo', p_user_id;
  END IF;

  -- Validar assigned_by (si viene)
  IF p_assigned_by IS NOT NULL THEN
    PERFORM 1 FROM clinicqueue.users u WHERE u.user_id=p_assigned_by AND u.is_active=true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'assigned_by % no existe o está inactivo', p_assigned_by;
    END IF;
  END IF;

  -- Validar ventana
  IF p_valid_from IS NOT NULL AND p_valid_to IS NOT NULL AND p_valid_to <= p_valid_from THEN
    RAISE EXCEPTION 'valid_to (%) debe ser mayor que valid_from (%)', p_valid_to, p_valid_from;
  END IF;

  INSERT INTO clinicqueue.station_users(station_id, user_id, is_enabled, valid_from, valid_to, assigned_by)
  VALUES (p_station_id, p_user_id, p_is_enabled, p_valid_from, p_valid_to, p_assigned_by)
  ON CONFLICT (station_id, user_id) DO UPDATE
    SET is_enabled  = EXCLUDED.is_enabled,
        valid_from  = EXCLUDED.valid_from,
        valid_to    = EXCLUDED.valid_to,
        assigned_by = EXCLUDED.assigned_by,
        assigned_at = now()
  RETURNING station_id, user_id, is_enabled, valid_from, valid_to, assigned_at, assigned_by
  INTO out_station_id, out_user_id, out_is_enabled, out_valid_from, out_valid_to, out_assigned_at, out_assigned_by;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.assign_user_to_station(p_station_id bigint, p_user_id bigint, p_assigned_by bigint, p_valid_from timestamp with time zone, p_valid_to timestamp with time zone, p_is_enabled boolean) OWNER TO postgres;

--
-- TOC entry 691 (class 1255 OID 55621)
-- Name: auto_no_show(integer); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.auto_no_show(p_limit integer DEFAULT 50) RETURNS TABLE(out_ticket_id bigint, out_code text, out_prefix text, out_tck_number integer, out_marked_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_now timestamptz := now();
BEGIN
  -- Tomar candidatos en batches para no bloquear
  WITH candidates AS (
    SELECT t.ticket_id
    FROM clinicqueue.tickets t
    JOIN clinicqueue.queue_settings qs ON qs.prefix = t.prefix
    WHERE t.status = 'LLAMADO'
      AND t.called_at IS NOT NULL
      AND (v_now - t.called_at) > qs.no_show_timeout
    ORDER BY t.called_at ASC
    LIMIT GREATEST(p_limit, 1)
    FOR UPDATE SKIP LOCKED
  ),
  upd AS (
    UPDATE clinicqueue.tickets t
    SET status   = 'NO_SHOW',
        ended_at = v_now,
        ended_by = NULL
    FROM candidates c
    WHERE t.ticket_id = c.ticket_id
    RETURNING t.ticket_id, t.code, t.prefix, t.tck_number, t.station_id, t.module_id
  )
  INSERT INTO clinicqueue.ticket_events(ticket_id, event_type, from_status, to_status, station_id, module_id, user_id, event_at, details)
  SELECT
    u.ticket_id,
    'NO_SHOW',
    'LLAMADO',
    'NO_SHOW',
    u.station_id,
    u.module_id,
    NULL,
    v_now,
    jsonb_build_object('auto', true)
  FROM upd u;

  RETURN QUERY
  SELECT u.ticket_id, u.code, u.prefix, u.tck_number, v_now
  FROM upd u;
END;
$$;


ALTER FUNCTION clinicqueue.auto_no_show(p_limit integer) OWNER TO postgres;

--
-- TOC entry 690 (class 1255 OID 55620)
-- Name: call_next_ticket(bigint, bigint); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.call_next_ticket(p_station_id bigint, p_user_id bigint) RETURNS TABLE(out_ticket_id bigint, out_code text, out_prefix text, out_tck_number integer, out_module_id bigint, out_station_id bigint, out_status clinicqueue.ticket_status, out_called_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_prefix text;
  v_module_id bigint;
  v_now timestamptz := now();
BEGIN
  -- 1) Validar estación activa
  SELECT s.prefix, s.module_id
    INTO v_prefix, v_module_id
  FROM clinicqueue.stations s
  WHERE s.station_id = p_station_id
    AND s.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Station % no existe o está inactiva', p_station_id;
  END IF;

  -- 2) Validar usuario activo
  PERFORM 1
  FROM clinicqueue.users u
  WHERE u.user_id = p_user_id
    AND u.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % no existe o está inactivo', p_user_id;
  END IF;

  -- 3) Validar autorización estación
  PERFORM 1
  FROM clinicqueue.station_users su
  WHERE su.station_id = p_station_id
    AND su.user_id = p_user_id
    AND su.is_enabled = true
    AND (su.valid_from IS NULL OR su.valid_from <= v_now)
    AND (su.valid_to   IS NULL OR su.valid_to   >  v_now);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % no está autorizado para operar Station %', p_user_id, p_station_id;
  END IF;

  -- ✅ REGLA #1: Solo 1 LLAMADO por estación
  PERFORM 1
  FROM clinicqueue.tickets t
  WHERE t.station_id = p_station_id
    AND t.status = 'LLAMADO';

  IF FOUND THEN
    RAISE EXCEPTION 'Station % ya tiene un ticket en estado LLAMADO. Debe iniciar/finalizar/no-show antes de llamar otro.', p_station_id;
  END IF;

  -- 4) Tomar el siguiente ticket EN_COLA del prefijo (sin módulo asignado)
  WITH next_ticket AS (
    SELECT t.ticket_id
    FROM clinicqueue.tickets t
    WHERE t.prefix = v_prefix
      AND t.status = 'EN_COLA'
      AND t.module_id IS NULL
    ORDER BY t.created_at ASC, t.ticket_id ASC
    FOR UPDATE SKIP LOCKED
    LIMIT 1
  )
  UPDATE clinicqueue.tickets t
     SET status     = 'LLAMADO',
         called_at  = v_now,
         station_id = p_station_id,
         module_id  = v_module_id,
         called_by  = p_user_id
  FROM next_ticket nt
  WHERE t.ticket_id = nt.ticket_id
  RETURNING
    t.ticket_id,
    t.code,
    t.prefix,
    t.tck_number,
    t.module_id,
    t.station_id,
    t.status,
    t.called_at
  INTO
    out_ticket_id,
    out_code,
    out_prefix,
    out_tck_number,
    out_module_id,
    out_station_id,
    out_status,
    out_called_at;

  IF out_ticket_id IS NULL THEN
    RETURN; -- no hay tickets en cola
  END IF;

  -- 5) Evento
  INSERT INTO clinicqueue.ticket_events(
    ticket_id, event_type, from_status, to_status, station_id, module_id, user_id, event_at, details
  )
  VALUES (
    out_ticket_id,
    'CALLED',
    'EN_COLA',
    'LLAMADO',
    out_station_id,
    out_module_id,
    p_user_id,
    v_now,
    jsonb_build_object('station_id', out_station_id, 'module_id', out_module_id)
  );

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.call_next_ticket(p_station_id bigint, p_user_id bigint) OWNER TO postgres;

--
-- TOC entry 689 (class 1255 OID 55601)
-- Name: cancel_ticket(bigint, bigint, text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.cancel_ticket(p_ticket_id bigint, p_user_id bigint, p_reason text DEFAULT NULL::text) RETURNS TABLE(out_ticket_id bigint, out_code text, out_prefix text, out_tck_number integer, out_status clinicqueue.ticket_status, out_ended_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_now timestamptz := now();
  v_status clinicqueue.ticket_status;
  v_station_id bigint;
  v_module_id bigint;
BEGIN
  -- 1) Validar usuario activo
  PERFORM 1
  FROM clinicqueue.users u
  WHERE u.user_id = p_user_id
    AND u.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % no existe o está inactivo', p_user_id;
  END IF;

  -- 2) Lock ticket + contexto
  SELECT t.status, t.station_id, t.module_id
    INTO v_status, v_station_id, v_module_id
  FROM clinicqueue.tickets t
  WHERE t.ticket_id = p_ticket_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ticket % no existe', p_ticket_id;
  END IF;

  -- 3) Reglas de cancelación
  IF v_status NOT IN ('EN_COLA','LLAMADO') THEN
    RAISE EXCEPTION 'Solo se puede cancelar un ticket EN_COLA o LLAMADO. Estado actual: %', v_status;
  END IF;

  -- Si fue llamado, exigir que el usuario esté autorizado en ESA estación
  IF v_status = 'LLAMADO' THEN
    IF v_station_id IS NULL THEN
      RAISE EXCEPTION 'Ticket % está LLAMADO pero no tiene station_id asignada', p_ticket_id;
    END IF;

    PERFORM 1
    FROM clinicqueue.station_users su
    WHERE su.station_id = v_station_id
      AND su.user_id = p_user_id
      AND su.is_enabled = true
      AND (su.valid_from IS NULL OR su.valid_from <= v_now)
      AND (su.valid_to   IS NULL OR su.valid_to   >  v_now);

    IF NOT FOUND THEN
      RAISE EXCEPTION 'User % no está autorizado para cancelar un ticket llamado en Station %',
        p_user_id, v_station_id;
    END IF;
  END IF;

  -- 4) Cancelar
  UPDATE clinicqueue.tickets t
  SET status   = 'CANCELADO',
      ended_at = v_now,
      ended_by = p_user_id,
      notes    = CASE
                   WHEN p_reason IS NULL OR length(trim(p_reason)) = 0 THEN t.notes
                   ELSE COALESCE(t.notes || E'\n', '') || 'CANCEL: ' || trim(p_reason)
                 END
  WHERE t.ticket_id = p_ticket_id
  RETURNING t.ticket_id, t.code, t.prefix, t.tck_number, t.status, t.ended_at
  INTO out_ticket_id, out_code, out_prefix, out_tck_number, out_status, out_ended_at;

  -- 5) Evento
  INSERT INTO clinicqueue.ticket_events(
    ticket_id, event_type, from_status, to_status, station_id, module_id, user_id, event_at, details
  )
  VALUES (
    out_ticket_id,
    'CANCELLED',
    v_status,
    'CANCELADO',
    v_station_id,
    v_module_id,
    p_user_id,
    v_now,
    jsonb_build_object('reason', p_reason)
  );

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.cancel_ticket(p_ticket_id bigint, p_user_id bigint, p_reason text) OWNER TO postgres;

--
-- TOC entry 726 (class 1255 OID 55872)
-- Name: close_daily_open_tickets(date, text, bigint, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.close_daily_open_tickets(p_operational_date date DEFAULT CURRENT_DATE, p_run_mode text DEFAULT 'MANUAL'::text, p_executed_by bigint DEFAULT NULL::bigint, p_preview_only boolean DEFAULT false) RETURNS TABLE(out_run_id bigint, out_ticket_id bigint, out_code text, out_prefix text, out_old_status clinicqueue.ticket_status, out_new_status clinicqueue.ticket_status, out_ticket_date date, out_closed_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_run_id bigint;
    v_now timestamptz := now();
    v_run_mode text := upper(trim(p_run_mode));
BEGIN
    IF v_run_mode NOT IN ('MANUAL', 'AUTO') THEN
        RAISE EXCEPTION 'p_run_mode inválido: %. Use MANUAL o AUTO', p_run_mode;
    END IF;

    -- Validar usuario si viene
    IF p_executed_by IS NOT NULL THEN
        PERFORM 1
        FROM clinicqueue.users u
        WHERE u.user_id = p_executed_by
          AND u.is_active = true;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'executed_by % no existe o está inactivo', p_executed_by;
        END IF;
    END IF;

    -- Preview: no escribe nada, solo muestra candidatos
    IF p_preview_only THEN
        RETURN QUERY
        SELECT
            NULL::bigint AS out_run_id,
            t.ticket_id,
            t.code,
            t.prefix,
            t.status AS out_old_status,
            'EXPIRADO'::clinicqueue.ticket_status AS out_new_status,
            t.ticket_date,
            NULL::timestamptz AS out_closed_at
        FROM clinicqueue.tickets t
        JOIN clinicqueue.queue_settings qs
          ON qs.prefix = t.prefix
        WHERE qs.mode = 'DAILY_RESET'
          AND qs.auto_close_open_tickets = true
          AND t.ticket_date < p_operational_date
          AND t.status IN ('EN_COLA', 'LLAMADO')
        ORDER BY t.ticket_date, t.prefix, t.tck_number;

        RETURN;
    END IF;

    INSERT INTO clinicqueue.daily_close_runs (
        run_mode,
        operational_date,
        started_at,
        executed_by
    )
    VALUES (
        v_run_mode,
        p_operational_date,
        v_now,
        p_executed_by
    )
    RETURNING run_id INTO v_run_id;

    RETURN QUERY
    WITH candidates AS (
        SELECT
            t.ticket_id,
            t.code,
            t.prefix,
            t.status AS old_status,
            t.ticket_date
        FROM clinicqueue.tickets t
        JOIN clinicqueue.queue_settings qs
          ON qs.prefix = t.prefix
        WHERE qs.mode = 'DAILY_RESET'
          AND qs.auto_close_open_tickets = true
          AND t.ticket_date < p_operational_date
          AND t.status IN ('EN_COLA', 'LLAMADO')
        FOR UPDATE SKIP LOCKED
    ),
    updated AS (
        UPDATE clinicqueue.tickets t
        SET
            status = 'EXPIRADO',
            ended_at = v_now,
            ended_by = p_executed_by
        FROM candidates c
        WHERE t.ticket_id = c.ticket_id
        RETURNING
            t.ticket_id,
            t.code,
            t.prefix,
            c.old_status,
            t.status AS new_status,
            t.ticket_date,
            t.ended_at
    ),
    inserted_events AS (
        INSERT INTO clinicqueue.ticket_events (
            ticket_id,
            event_type,
            from_status,
            to_status,
            user_id,
            event_at,
            details
        )
        SELECT
            u.ticket_id,
            'AUTO_CLOSED',
            u.old_status,
            u.new_status,
            p_executed_by,
            v_now,
            jsonb_build_object(
                'reason', 'AUTO_DAY_CLOSE',
                'run_id', v_run_id,
                'run_mode', v_run_mode,
                'operational_date', p_operational_date
            )
        FROM updated u
        RETURNING ticket_id
    )
    SELECT
        v_run_id,
        u.ticket_id,
        u.code,
        u.prefix,
        u.old_status,
        u.new_status,
        u.ticket_date,
        u.ended_at
    FROM updated u
    ORDER BY u.ticket_date, u.prefix, u.ticket_id;

    UPDATE clinicqueue.daily_close_runs r
    SET
        finished_at = now(),
        tickets_closed = (
            SELECT count(*)
            FROM clinicqueue.ticket_events te
            WHERE te.event_type = 'AUTO_CLOSED'
              AND (te.details ->> 'run_id')::bigint = v_run_id
        )
    WHERE r.run_id = v_run_id;
END;
$$;


ALTER FUNCTION clinicqueue.close_daily_open_tickets(p_operational_date date, p_run_mode text, p_executed_by bigint, p_preview_only boolean) OWNER TO postgres;

--
-- TOC entry 717 (class 1255 OID 55661)
-- Name: create_display_board(text, text, text, boolean, integer, boolean, boolean, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.create_display_board(p_board_code text, p_board_name text, p_location text DEFAULT NULL::text, p_show_last_called boolean DEFAULT true, p_show_last_in_service integer DEFAULT 3, p_show_waiting_count boolean DEFAULT true, p_sound_enabled_override boolean DEFAULT NULL::boolean, p_is_active boolean DEFAULT true) RETURNS TABLE(out_board_id bigint, out_board_code text, out_board_name text, out_location text, out_show_last_called boolean, out_show_last_in_service integer, out_show_waiting_count boolean, out_sound_enabled_override boolean, out_is_active boolean, out_created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_code text := upper(trim(p_board_code));
BEGIN
  IF v_code IS NULL OR length(v_code) < 3 THEN
    RAISE EXCEPTION 'board_code inválido: %', p_board_code;
  END IF;

  IF p_show_last_in_service IS NOT NULL AND p_show_last_in_service < 0 THEN
    RAISE EXCEPTION 'show_last_in_service debe ser >= 0';
  END IF;

  INSERT INTO clinicqueue.display_boards(
    board_code, board_name, location,
    show_last_called, show_last_in_service, show_waiting_count,
    sound_enabled_override, is_active
  )
  VALUES (
    v_code,
    trim(p_board_name),
    CASE WHEN p_location IS NULL OR length(trim(p_location))=0 THEN NULL ELSE trim(p_location) END,
    COALESCE(p_show_last_called, true),
    COALESCE(p_show_last_in_service, 3),
    COALESCE(p_show_waiting_count, true),
    p_sound_enabled_override,
    COALESCE(p_is_active, true)
  )
  RETURNING
    board_id, board_code, board_name, location,
    show_last_called, show_last_in_service, show_waiting_count,
    sound_enabled_override, is_active, created_at
  INTO
    out_board_id, out_board_code, out_board_name, out_location,
    out_show_last_called, out_show_last_in_service, out_show_waiting_count,
    out_sound_enabled_override, out_is_active, out_created_at;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.create_display_board(p_board_code text, p_board_name text, p_location text, p_show_last_called boolean, p_show_last_in_service integer, p_show_waiting_count boolean, p_sound_enabled_override boolean, p_is_active boolean) OWNER TO postgres;

--
-- TOC entry 713 (class 1255 OID 55657)
-- Name: create_module(text, text, text, integer); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.create_module(p_prefix text, p_module_code text, p_module_name text, p_display_order integer DEFAULT 1) RETURNS TABLE(out_module_id bigint, out_prefix text, out_module_code text, out_module_name text, out_display_order integer, out_is_active boolean, out_created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_prefix text := upper(trim(p_prefix));
  v_code text := upper(trim(p_module_code));
BEGIN
  -- Validar prefijo existente
  PERFORM 1 FROM clinicqueue.queue_settings qs WHERE qs.prefix = v_prefix;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prefijo % no existe en clinicqueue.queue_settings', v_prefix;
  END IF;

  -- Validar que module_code empiece con el prefijo (C01, L01, E01...)
  IF left(v_code, 1) <> v_prefix THEN
    RAISE EXCEPTION 'module_code % no coincide con prefix % (ej: %01)', v_code, v_prefix, v_prefix;
  END IF;

  IF p_display_order IS NULL OR p_display_order < 1 THEN
    RAISE EXCEPTION 'display_order debe ser >= 1';
  END IF;

  INSERT INTO clinicqueue.modules(prefix, module_code, module_name, display_order)
  VALUES (v_prefix, v_code, trim(p_module_name), p_display_order)
  RETURNING module_id, prefix, module_code, module_name, display_order, is_active, created_at
  INTO out_module_id, out_prefix, out_module_code, out_module_name, out_display_order, out_is_active, out_created_at;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.create_module(p_prefix text, p_module_code text, p_module_name text, p_display_order integer) OWNER TO postgres;

--
-- TOC entry 694 (class 1255 OID 55626)
-- Name: create_role(text, text, text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.create_role(p_role_code text, p_role_name text, p_description text DEFAULT NULL::text) RETURNS TABLE(out_role_id bigint, out_role_code text, out_role_name text, out_description text, out_is_active boolean, out_created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO clinicqueue.roles(role_code, role_name, description)
  VALUES (
    upper(trim(p_role_code)),
    trim(p_role_name),
    CASE WHEN p_description IS NULL OR length(trim(p_description))=0 THEN NULL ELSE trim(p_description) END
  )
  RETURNING role_id, role_code, role_name, description, is_active, created_at
  INTO out_role_id, out_role_code, out_role_name, out_description, out_is_active, out_created_at;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.create_role(p_role_code text, p_role_name text, p_description text) OWNER TO postgres;

--
-- TOC entry 700 (class 1255 OID 55632)
-- Name: create_station(text, text, text, bigint); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.create_station(p_station_code text, p_station_name text, p_prefix text, p_module_id bigint DEFAULT NULL::bigint) RETURNS TABLE(out_station_id bigint, out_station_code text, out_station_name text, out_prefix text, out_module_id bigint, out_is_active boolean, out_created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- validar prefijo existe
  PERFORM 1 FROM clinicqueue.queue_settings qs WHERE qs.prefix = upper(trim(p_prefix));
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prefijo % no existe en clinicqueue.queue_settings', upper(trim(p_prefix));
  END IF;

  -- validar módulo si viene
  IF p_module_id IS NOT NULL THEN
    PERFORM 1 FROM clinicqueue.modules m
    WHERE m.module_id = p_module_id
      AND m.is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'module_id % no existe o está inactivo', p_module_id;
    END IF;
  END IF;

  INSERT INTO clinicqueue.stations(station_code, station_name, prefix, module_id)
  VALUES (
    upper(trim(p_station_code)),
    trim(p_station_name),
    upper(trim(p_prefix)),
    p_module_id
  )
  RETURNING station_id, station_code, station_name, prefix, module_id, is_active, created_at
  INTO out_station_id, out_station_code, out_station_name, out_prefix, out_module_id, out_is_active, out_created_at;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.create_station(p_station_code text, p_station_name text, p_prefix text, p_module_id bigint) OWNER TO postgres;

--
-- TOC entry 682 (class 1255 OID 55594)
-- Name: create_ticket(text, bigint, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.create_ticket(p_prefix text, p_created_by bigint DEFAULT NULL::bigint, p_is_walkin boolean DEFAULT true) RETURNS TABLE(out_ticket_id bigint, out_prefix text, out_tck_number integer, out_code text, out_status clinicqueue.ticket_status)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_prefix text := upper(trim(p_prefix::text));
  v_mode text;
  v_min int;
  v_max int;
  v_key text;
  v_last int;
  v_try int := 0;
  v_candidate int;

  v_max_active int;
  v_allow_walkins boolean;
  v_active_count int;
BEGIN
  -- settings
  SELECT qs.mode, qs.min_number, qs.max_number, qs.max_active, qs.allow_walkins
    INTO v_mode, v_min, v_max, v_max_active, v_allow_walkins
  FROM clinicqueue.queue_settings qs
  WHERE qs.prefix = v_prefix;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Prefijo % no existe en clinicqueue.queue_settings', v_prefix;
  END IF;

  IF p_is_walkin AND NOT v_allow_walkins THEN
    RAISE EXCEPTION 'La cola % no permite walk-ins (solo con cita/check-in)', v_prefix;
  END IF;

  -- cola llena?
  IF v_max_active IS NOT NULL THEN
    SELECT count(*) INTO v_active_count
    FROM clinicqueue.tickets t
    WHERE t.prefix = v_prefix
      AND t.status IN ('EN_COLA','LLAMADO','EN_ATENCION');

    IF v_active_count >= v_max_active THEN
      RAISE EXCEPTION 'Cola % llena. Activos: %, Max: %', v_prefix, v_active_count, v_max_active;
    END IF;
  END IF;

  -- counter_key según modo
  v_key := CASE WHEN v_mode = 'DAILY_RESET'
                THEN to_char(current_date, 'YYYY-MM-DD')
                ELSE 'GLOBAL' END;

  -- asegurar counter y lock
  INSERT INTO clinicqueue.queue_counters(prefix, counter_key, last_number)
  VALUES (v_prefix, v_key, 0)
  ON CONFLICT (prefix, counter_key) DO NOTHING;

  SELECT qc.last_number
    INTO v_last
  FROM clinicqueue.queue_counters qc
  WHERE qc.prefix = v_prefix AND qc.counter_key = v_key
  FOR UPDATE;

  -- buscar número libre (01-99)
  WHILE v_try < (v_max - v_min + 1) LOOP
    v_try := v_try + 1;

    v_candidate := CASE
      WHEN v_last < v_min OR v_last > v_max THEN v_min
      WHEN v_last + 1 > v_max THEN v_min
      ELSE v_last + 1
    END;

    BEGIN
      INSERT INTO clinicqueue.tickets(prefix, tck_number, code, status, created_by)
      VALUES (v_prefix, v_candidate, v_prefix || lpad(v_candidate::text, 2, '0'), 'EN_COLA', p_created_by)
      RETURNING
        ticket_id,
        prefix,
        tck_number,
        code,
        status
      INTO
        out_ticket_id,
        out_prefix,
        out_tck_number,
        out_code,
        out_status;

      UPDATE clinicqueue.queue_counters
        SET last_number = v_candidate, updated_at = now()
      WHERE prefix = v_prefix AND counter_key = v_key;

      -- evento (opcional pero recomendado)
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


ALTER FUNCTION clinicqueue.create_ticket(p_prefix text, p_created_by bigint, p_is_walkin boolean) OWNER TO postgres;

--
-- TOC entry 725 (class 1255 OID 55671)
-- Name: create_user(text, text, text, text, text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.create_user(p_username text, p_display_name text, p_password_hash text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text) RETURNS TABLE(out_user_id bigint, out_username text, out_display_name text, out_email text, out_phone text, out_is_active boolean, out_created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF p_password_hash IS NULL OR length(trim(p_password_hash)) = 0 THEN
    RAISE EXCEPTION 'password_hash is required';
  END IF;

  INSERT INTO clinicqueue.users(username, display_name, password_hash, email, phone)
  VALUES (
    lower(trim(p_username)),
    trim(p_display_name),
    trim(p_password_hash),
    CASE WHEN p_email IS NULL OR length(trim(p_email))=0 THEN NULL ELSE lower(trim(p_email)) END,
    CASE WHEN p_phone IS NULL OR length(trim(p_phone))=0 THEN NULL ELSE trim(p_phone) END
  )
  RETURNING
    user_id, username, display_name, email, phone, is_active, created_at
  INTO
    out_user_id, out_username, out_display_name, out_email, out_phone, out_is_active, out_created_at;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.create_user(p_username text, p_display_name text, p_password_hash text, p_email text, p_phone text) OWNER TO postgres;

--
-- TOC entry 686 (class 1255 OID 55599)
-- Name: finish_ticket(bigint, bigint, bigint, text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.finish_ticket(p_ticket_id bigint, p_station_id bigint, p_user_id bigint, p_notes text DEFAULT NULL::text) RETURNS TABLE(out_ticket_id bigint, out_code text, out_prefix text, out_tck_number integer, out_station_id bigint, out_module_id bigint, out_status clinicqueue.ticket_status, out_ended_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_now timestamptz := now();
  v_status clinicqueue.ticket_status;
  v_station_from_ticket bigint;
  v_module_from_ticket bigint;
BEGIN
  -- 1) Validar estación activa
  PERFORM 1
  FROM clinicqueue.stations s
  WHERE s.station_id = p_station_id
    AND s.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Station % no existe o está inactiva', p_station_id;
  END IF;

  -- 2) Validar usuario activo + autorización estación
  PERFORM 1
  FROM clinicqueue.users u
  WHERE u.user_id = p_user_id
    AND u.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % no existe o está inactivo', p_user_id;
  END IF;

  PERFORM 1
  FROM clinicqueue.station_users su
  WHERE su.station_id = p_station_id
    AND su.user_id = p_user_id
    AND su.is_enabled = true
    AND (su.valid_from IS NULL OR su.valid_from <= v_now)
    AND (su.valid_to   IS NULL OR su.valid_to   >  v_now);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % no está autorizado para operar Station %', p_user_id, p_station_id;
  END IF;

  -- 3) Leer ticket y validar ownership (lock)
  SELECT t.status, t.station_id, t.module_id
    INTO v_status, v_station_from_ticket, v_module_from_ticket
  FROM clinicqueue.tickets t
  WHERE t.ticket_id = p_ticket_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ticket % no existe', p_ticket_id;
  END IF;

  IF v_status <> 'EN_ATENCION' THEN
    RAISE EXCEPTION 'Solo se puede finalizar un ticket en estado EN_ATENCION. Estado actual: %', v_status;
  END IF;

  IF v_station_from_ticket IS DISTINCT FROM p_station_id THEN
    RAISE EXCEPTION 'Ticket % pertenece a otra estación (%). No puedes finalizar desde (%)',
      p_ticket_id, v_station_from_ticket, p_station_id;
  END IF;

  -- 4) Finalizar: EN_ATENCION -> FINALIZADO
  UPDATE clinicqueue.tickets t
  SET status   = 'FINALIZADO',
      ended_at = v_now,
      ended_by = p_user_id,
      notes    = COALESCE(p_notes, t.notes)
  WHERE t.ticket_id = p_ticket_id
  RETURNING
    t.ticket_id, t.code, t.prefix, t.tck_number, t.station_id, t.module_id, t.status, t.ended_at
  INTO
    out_ticket_id, out_code, out_prefix, out_tck_number, out_station_id, out_module_id, out_status, out_ended_at;

  -- 5) Evento
  INSERT INTO clinicqueue.ticket_events(
    ticket_id, event_type, from_status, to_status, station_id, module_id, user_id, event_at, details
  )
  VALUES (
    out_ticket_id,
    'FINISHED',
    'EN_ATENCION',
    'FINALIZADO',
    out_station_id,
    out_module_id,
    p_user_id,
    v_now,
    CASE
      WHEN p_notes IS NULL THEN jsonb_build_object('action','FINISH')
      ELSE jsonb_build_object('action','FINISH','notes',p_notes)
    END
  );

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.finish_ticket(p_ticket_id bigint, p_station_id bigint, p_user_id bigint, p_notes text) OWNER TO postgres;

--
-- TOC entry 626 (class 1255 OID 55618)
-- Name: get_board_in_service(text, integer); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.get_board_in_service(p_board_code text, p_limit integer DEFAULT 3) RETURNS TABLE(station_code text, station_name text, module_code text, ticket_id bigint, ticket_code text, started_at timestamp with time zone)
    LANGUAGE sql
    AS $$
  SELECT
    s.station_code,
    s.station_name,
    s.module_code,
    s.ticket_id,
    s.ticket_code,
    s.started_at
  FROM clinicqueue.v_board_in_service s
  WHERE s.board_code = upper(trim(p_board_code))
  ORDER BY s.started_at DESC NULLS LAST
  LIMIT GREATEST(p_limit, 0);
$$;


ALTER FUNCTION clinicqueue.get_board_in_service(p_board_code text, p_limit integer) OWNER TO postgres;

--
-- TOC entry 625 (class 1255 OID 55617)
-- Name: get_board_now_calling(text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.get_board_now_calling(p_board_code text) RETURNS TABLE(station_code text, station_name text, module_code text, ticket_id bigint, ticket_code text, called_at timestamp with time zone)
    LANGUAGE sql
    AS $$
  SELECT
    c.station_code,
    c.station_name,
    c.module_code,
    c.ticket_id,
    c.ticket_code,
    c.called_at
  FROM clinicqueue.v_board_now_calling c
  WHERE c.board_code = upper(trim(p_board_code))
  ORDER BY c.called_at DESC;
$$;


ALTER FUNCTION clinicqueue.get_board_now_calling(p_board_code text) OWNER TO postgres;

--
-- TOC entry 724 (class 1255 OID 55670)
-- Name: get_board_snapshot(text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.get_board_snapshot(p_board_code text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_code text := upper(trim(p_board_code));

  v_board_id bigint;
  v_board_name text;
  v_location text;

  v_show_last_called boolean;
  v_show_last_in_service int;
  v_show_waiting_count boolean;
  v_sound_override boolean;

  v_now_calling jsonb := '[]'::jsonb;
  v_in_service jsonb := '[]'::jsonb;
  v_waiting jsonb := '[]'::jsonb;

  v_sound_effective boolean := false;
  v_now timestamptz := now();
BEGIN
  -- 1) Cargar configuración del board
  SELECT
    b.board_id,
    b.board_name,
    b.location,
    b.show_last_called,
    b.show_last_in_service,
    b.show_waiting_count,
    b.sound_enabled_override
  INTO
    v_board_id,
    v_board_name,
    v_location,
    v_show_last_called,
    v_show_last_in_service,
    v_show_waiting_count,
    v_sound_override
  FROM clinicqueue.display_boards b
  WHERE b.board_code = v_code
    AND b.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Board % no existe o está inactivo', v_code;
  END IF;

  IF v_show_last_in_service IS NULL OR v_show_last_in_service < 0 THEN
    v_show_last_in_service := 0;
  END IF;

  -- 2) now_calling (1 LLAMADO por estación, para estaciones del board)
  IF v_show_last_called THEN
    WITH ranked AS (
      SELECT
        bs.display_order,
        s.station_id,
        s.station_code,
        s.station_name,
        m.module_code,
        t.ticket_id,
        t.code AS ticket_code,
        t.called_at,
        row_number() OVER (PARTITION BY s.station_id ORDER BY t.called_at DESC, t.ticket_id DESC) AS rn
      FROM clinicqueue.board_stations bs
      JOIN clinicqueue.stations s ON s.station_id = bs.station_id AND s.is_active = true
      LEFT JOIN clinicqueue.modules m ON m.module_id = s.module_id
      JOIN clinicqueue.tickets t ON t.station_id = s.station_id AND t.status = 'LLAMADO'
      WHERE bs.board_id = v_board_id
        AND bs.is_enabled = true
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.display_order), '[]'::jsonb)
      INTO v_now_calling
    FROM (
      SELECT
        display_order,
        station_code,
        station_name,
        module_code,
        ticket_id,
        ticket_code,
        called_at,
        EXTRACT(EPOCH FROM (v_now - called_at))::bigint AS called_seconds_ago
      FROM ranked
      WHERE rn = 1
    ) x;
  END IF;

  -- 3) in_service (últimos N EN_ATENCION del board)
  IF v_show_last_in_service > 0 THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(y) ORDER BY y.started_at DESC), '[]'::jsonb)
      INTO v_in_service
    FROM (
      SELECT
        bs.display_order,
        s.station_code,
        s.station_name,
        m.module_code,
        t.ticket_id,
        t.code AS ticket_code,
        t.started_at,
        EXTRACT(EPOCH FROM (v_now - t.started_at))::bigint AS in_service_seconds
      FROM clinicqueue.board_stations bs
      JOIN clinicqueue.stations s ON s.station_id = bs.station_id AND s.is_active = true
      LEFT JOIN clinicqueue.modules m ON m.module_id = s.module_id
      JOIN clinicqueue.tickets t ON t.station_id = s.station_id AND t.status = 'EN_ATENCION'
      WHERE bs.board_id = v_board_id
        AND bs.is_enabled = true
      ORDER BY t.started_at DESC NULLS LAST
      LIMIT v_show_last_in_service
    ) y;
  END IF;

  -- 4) waiting_counts (por prefijo, solo los prefijos presentes en estaciones del board)
  IF v_show_waiting_count THEN
    WITH bp AS (
      SELECT DISTINCT s.prefix
      FROM clinicqueue.board_stations bs
      JOIN clinicqueue.stations s ON s.station_id = bs.station_id
      WHERE bs.board_id = v_board_id
        AND bs.is_enabled = true
    )
    SELECT COALESCE(jsonb_agg(to_jsonb(z) ORDER BY z.prefix), '[]'::jsonb)
      INTO v_waiting
    FROM (
      SELECT
        t.prefix,
        count(*)::bigint AS waiting_count
      FROM clinicqueue.tickets t
      JOIN bp ON bp.prefix = t.prefix
      WHERE t.status = 'EN_COLA'
      GROUP BY t.prefix
    ) z;
  END IF;

  -- 5) sound_enabled_effective
  -- Si hay override, manda ese valor.
  -- Si no hay override: true si alguna cola (prefijo) del board tiene sound_enabled=true en queue_settings.
  IF v_sound_override IS NOT NULL THEN
    v_sound_effective := v_sound_override;
  ELSE
    WITH bp AS (
      SELECT DISTINCT s.prefix
      FROM clinicqueue.board_stations bs
      JOIN clinicqueue.stations s ON s.station_id = bs.station_id
      WHERE bs.board_id = v_board_id
        AND bs.is_enabled = true
    )
    SELECT COALESCE(bool_or(qs.sound_enabled), false)
      INTO v_sound_effective
    FROM bp
    JOIN clinicqueue.queue_settings qs ON qs.prefix = bp.prefix;
  END IF;

  RETURN jsonb_build_object(
    'board', jsonb_build_object(
      'board_id', v_board_id,
      'board_code', v_code,
      'board_name', v_board_name,
      'location', v_location,
      'show_last_called', v_show_last_called,
      'show_last_in_service', v_show_last_in_service,
      'show_waiting_count', v_show_waiting_count,
      'sound_enabled_override', v_sound_override,
      'sound_enabled_effective', v_sound_effective
    ),
    'generated_at', v_now,
    'now_calling', v_now_calling,
    'in_service', v_in_service,
    'waiting_counts', v_waiting
  );
END;
$$;


ALTER FUNCTION clinicqueue.get_board_snapshot(p_board_code text) OWNER TO postgres;

--
-- TOC entry 681 (class 1255 OID 55668)
-- Name: get_board_stations(bigint, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.get_board_stations(p_board_id bigint, p_only_enabled boolean DEFAULT false) RETURNS TABLE(board_id bigint, station_id bigint, display_order integer, is_enabled boolean, station_code text, station_name text, prefix text, module_id bigint, module_code text, module_name text, station_is_active boolean)
    LANGUAGE sql
    AS $$
  SELECT
    bs.board_id,
    bs.station_id,
    bs.display_order,
    bs.is_enabled,
    s.station_code,
    s.station_name,
    s.prefix,
    s.module_id,
    m.module_code,
    m.module_name,
    s.is_active AS station_is_active
  FROM clinicqueue.board_stations bs
  JOIN clinicqueue.stations s ON s.station_id = bs.station_id
  LEFT JOIN clinicqueue.modules m ON m.module_id = s.module_id
  WHERE bs.board_id = p_board_id
    AND (p_only_enabled = false OR bs.is_enabled = true)
  ORDER BY bs.display_order, s.station_code;
$$;


ALTER FUNCTION clinicqueue.get_board_stations(p_board_id bigint, p_only_enabled boolean) OWNER TO postgres;

--
-- TOC entry 627 (class 1255 OID 55619)
-- Name: get_board_waiting_counts(text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.get_board_waiting_counts(p_board_code text) RETURNS TABLE(prefix text, waiting_count bigint)
    LANGUAGE sql
    AS $$
  WITH bp AS (
    SELECT DISTINCT v.prefix
    FROM clinicqueue.v_board_enabled_stations v
    WHERE v.board_code = upper(trim(p_board_code))
  )
  SELECT
    t.prefix,
    count(*) AS waiting_count
  FROM clinicqueue.tickets t
  JOIN bp ON bp.prefix = t.prefix
  WHERE t.status = 'EN_COLA'
  GROUP BY t.prefix
  ORDER BY t.prefix;
$$;


ALTER FUNCTION clinicqueue.get_board_waiting_counts(p_board_code text) OWNER TO postgres;

--
-- TOC entry 720 (class 1255 OID 55664)
-- Name: get_display_boards(boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.get_display_boards(p_only_active boolean DEFAULT false) RETURNS TABLE(board_id bigint, board_code text, board_name text, location text, show_last_called boolean, show_last_in_service integer, show_waiting_count boolean, sound_enabled_override boolean, is_active boolean, created_at timestamp with time zone, updated_at timestamp with time zone)
    LANGUAGE sql
    AS $$
  SELECT
    b.board_id,
    b.board_code,
    b.board_name,
    b.location,
    b.show_last_called,
    b.show_last_in_service,
    b.show_waiting_count,
    b.sound_enabled_override,
    b.is_active,
    b.created_at,
    b.updated_at
  FROM clinicqueue.display_boards b
  WHERE (p_only_active = false OR b.is_active = true)
  ORDER BY b.board_code;
$$;


ALTER FUNCTION clinicqueue.get_display_boards(p_only_active boolean) OWNER TO postgres;

--
-- TOC entry 716 (class 1255 OID 55660)
-- Name: get_modules(text, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.get_modules(p_prefix text DEFAULT NULL::text, p_only_active boolean DEFAULT false) RETURNS TABLE(module_id bigint, prefix text, module_code text, module_name text, display_order integer, is_active boolean)
    LANGUAGE sql
    AS $$
  SELECT
    m.module_id,
    m.prefix,
    m.module_code,
    m.module_name,
    m.display_order,
    m.is_active
  FROM clinicqueue.modules m
  WHERE (p_prefix IS NULL OR m.prefix = upper(trim(p_prefix)))
    AND (p_only_active = false OR m.is_active = true)
  ORDER BY m.prefix, m.display_order, m.module_code;
$$;


ALTER FUNCTION clinicqueue.get_modules(p_prefix text, p_only_active boolean) OWNER TO postgres;

--
-- TOC entry 711 (class 1255 OID 55647)
-- Name: get_queue_settings(text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.get_queue_settings(p_prefix text DEFAULT NULL::text) RETURNS TABLE(prefix text, mode text, min_number integer, max_number integer, max_active integer, allow_walkins boolean, no_show_timeout interval, sound_enabled boolean, created_at timestamp with time zone, updated_at timestamp with time zone)
    LANGUAGE sql
    AS $$
  SELECT
    qs.prefix,
    qs.mode,
    qs.min_number,
    qs.max_number,
    qs.max_active,
    qs.allow_walkins,
    qs.no_show_timeout,
    qs.sound_enabled,
    qs.created_at,
    qs.updated_at
  FROM clinicqueue.queue_settings qs
  WHERE (p_prefix IS NULL OR qs.prefix = upper(trim(p_prefix)))
  ORDER BY qs.prefix;
$$;


ALTER FUNCTION clinicqueue.get_queue_settings(p_prefix text) OWNER TO postgres;

--
-- TOC entry 683 (class 1255 OID 55669)
-- Name: get_station_boards(bigint, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.get_station_boards(p_station_id bigint, p_only_enabled boolean DEFAULT false) RETURNS TABLE(board_id bigint, board_code text, board_name text, location text, is_active boolean, station_id bigint, display_order integer, is_enabled boolean)
    LANGUAGE sql
    AS $$
  SELECT
    b.board_id,
    b.board_code,
    b.board_name,
    b.location,
    b.is_active,
    bs.station_id,
    bs.display_order,
    bs.is_enabled
  FROM clinicqueue.board_stations bs
  JOIN clinicqueue.display_boards b ON b.board_id = bs.board_id
  WHERE bs.station_id = p_station_id
    AND (p_only_enabled = false OR bs.is_enabled = true)
  ORDER BY b.board_code, bs.display_order;
$$;


ALTER FUNCTION clinicqueue.get_station_boards(p_station_id bigint, p_only_enabled boolean) OWNER TO postgres;

--
-- TOC entry 708 (class 1255 OID 55640)
-- Name: get_station_users(bigint); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.get_station_users(p_station_id bigint) RETURNS TABLE(user_id bigint, username text, display_name text, is_active boolean, is_enabled boolean, valid_from timestamp with time zone, valid_to timestamp with time zone, assigned_at timestamp with time zone, assigned_by bigint)
    LANGUAGE sql
    AS $$
  SELECT
    u.user_id,
    u.username,
    u.display_name,
    u.is_active,
    su.is_enabled,
    su.valid_from,
    su.valid_to,
    su.assigned_at,
    su.assigned_by
  FROM clinicqueue.station_users su
  JOIN clinicqueue.users u ON u.user_id = su.user_id
  WHERE su.station_id = p_station_id
  ORDER BY u.display_name;
$$;


ALTER FUNCTION clinicqueue.get_station_users(p_station_id bigint) OWNER TO postgres;

--
-- TOC entry 703 (class 1255 OID 55635)
-- Name: get_stations(text, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.get_stations(p_prefix text DEFAULT NULL::text, p_only_active boolean DEFAULT false) RETURNS TABLE(station_id bigint, station_code text, station_name text, prefix text, module_id bigint, module_code text, module_name text, is_active boolean)
    LANGUAGE sql
    AS $$
  SELECT
    s.station_id,
    s.station_code,
    s.station_name,
    s.prefix,
    s.module_id,
    m.module_code,
    m.module_name,
    s.is_active
  FROM clinicqueue.stations s
  LEFT JOIN clinicqueue.modules m ON m.module_id = s.module_id
  WHERE (p_prefix IS NULL OR s.prefix = upper(trim(p_prefix)))
    AND (p_only_active = false OR s.is_active = true)
  ORDER BY s.prefix, s.station_code;
$$;


ALTER FUNCTION clinicqueue.get_stations(p_prefix text, p_only_active boolean) OWNER TO postgres;

--
-- TOC entry 699 (class 1255 OID 55631)
-- Name: get_user_roles(bigint); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.get_user_roles(p_user_id bigint) RETURNS TABLE(role_id bigint, role_code text, role_name text, is_active boolean, assigned_at timestamp with time zone, assigned_by bigint)
    LANGUAGE sql
    AS $$
  SELECT
    r.role_id,
    r.role_code,
    r.role_name,
    r.is_active,
    ur.assigned_at,
    ur.assigned_by
  FROM clinicqueue.user_roles ur
  JOIN clinicqueue.roles r ON r.role_id = ur.role_id
  WHERE ur.user_id = p_user_id
  ORDER BY r.role_code;
$$;


ALTER FUNCTION clinicqueue.get_user_roles(p_user_id bigint) OWNER TO postgres;

--
-- TOC entry 709 (class 1255 OID 55641)
-- Name: get_user_stations(bigint); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.get_user_stations(p_user_id bigint) RETURNS TABLE(station_id bigint, station_code text, station_name text, prefix text, is_active boolean, is_enabled boolean, valid_from timestamp with time zone, valid_to timestamp with time zone, assigned_at timestamp with time zone)
    LANGUAGE sql
    AS $$
  SELECT
    s.station_id,
    s.station_code,
    s.station_name,
    s.prefix,
    s.is_active,
    su.is_enabled,
    su.valid_from,
    su.valid_to,
    su.assigned_at
  FROM clinicqueue.station_users su
  JOIN clinicqueue.stations s ON s.station_id = su.station_id
  WHERE su.user_id = p_user_id
  ORDER BY s.prefix, s.station_code;
$$;


ALTER FUNCTION clinicqueue.get_user_stations(p_user_id bigint) OWNER TO postgres;

--
-- TOC entry 687 (class 1255 OID 55600)
-- Name: mark_no_show(bigint, bigint, bigint, text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.mark_no_show(p_ticket_id bigint, p_station_id bigint, p_user_id bigint, p_reason text DEFAULT NULL::text) RETURNS TABLE(out_ticket_id bigint, out_code text, out_prefix text, out_tck_number integer, out_station_id bigint, out_module_id bigint, out_status clinicqueue.ticket_status, out_ended_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_now timestamptz := now();
  v_status clinicqueue.ticket_status;
  v_station_from_ticket bigint;
  v_module_from_ticket bigint;
BEGIN
  -- validar estación
  PERFORM 1 FROM clinicqueue.stations s WHERE s.station_id=p_station_id AND s.is_active=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'Station % no existe o está inactiva', p_station_id; END IF;

  -- validar usuario + autorización
  PERFORM 1 FROM clinicqueue.users u WHERE u.user_id=p_user_id AND u.is_active=true;
  IF NOT FOUND THEN RAISE EXCEPTION 'User % no existe o está inactivo', p_user_id; END IF;

  PERFORM 1
  FROM clinicqueue.station_users su
  WHERE su.station_id=p_station_id AND su.user_id=p_user_id AND su.is_enabled=true
    AND (su.valid_from IS NULL OR su.valid_from <= v_now)
    AND (su.valid_to   IS NULL OR su.valid_to   >  v_now);
  IF NOT FOUND THEN RAISE EXCEPTION 'User % no está autorizado para operar Station %', p_user_id, p_station_id; END IF;

  -- lock ticket
  SELECT t.status, t.station_id, t.module_id
    INTO v_status, v_station_from_ticket, v_module_from_ticket
  FROM clinicqueue.tickets t
  WHERE t.ticket_id = p_ticket_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Ticket % no existe', p_ticket_id; END IF;

  IF v_status <> 'LLAMADO' THEN
    RAISE EXCEPTION 'NO_SHOW solo aplica si el ticket está LLAMADO. Estado actual: %', v_status;
  END IF;

  IF v_station_from_ticket IS DISTINCT FROM p_station_id THEN
    RAISE EXCEPTION 'Ticket % fue llamado por otra estación (%). No puedes marcar NO_SHOW desde (%)',
      p_ticket_id, v_station_from_ticket, p_station_id;
  END IF;

  -- update
  UPDATE clinicqueue.tickets t
  SET status   = 'NO_SHOW',
      ended_at = v_now,
      ended_by = p_user_id
  WHERE t.ticket_id = p_ticket_id
  RETURNING t.ticket_id, t.code, t.prefix, t.tck_number, t.station_id, t.module_id, t.status, t.ended_at
  INTO out_ticket_id, out_code, out_prefix, out_tck_number, out_station_id, out_module_id, out_status, out_ended_at;

  -- event
  INSERT INTO clinicqueue.ticket_events(ticket_id, event_type, from_status, to_status, station_id, module_id, user_id, event_at, details)
  VALUES (
    out_ticket_id,
    'NO_SHOW',
    'LLAMADO',
    'NO_SHOW',
    out_station_id,
    out_module_id,
    p_user_id,
    v_now,
    jsonb_build_object('reason', p_reason)
  );

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.mark_no_show(p_ticket_id bigint, p_station_id bigint, p_user_id bigint, p_reason text) OWNER TO postgres;

--
-- TOC entry 684 (class 1255 OID 55597)
-- Name: recall_ticket(bigint, bigint, bigint, text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.recall_ticket(p_ticket_id bigint, p_station_id bigint, p_user_id bigint, p_reason text DEFAULT NULL::text) RETURNS TABLE(out_ticket_id bigint, out_code text, out_prefix text, out_tck_number integer, out_station_id bigint, out_module_id bigint, out_status clinicqueue.ticket_status, out_called_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_now timestamptz := now();
  v_status clinicqueue.ticket_status;
  v_station_from_ticket bigint;
  v_module_from_ticket bigint;
BEGIN
  -- 1) Validar estación activa
  PERFORM 1
  FROM clinicqueue.stations s
  WHERE s.station_id = p_station_id
    AND s.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Station % no existe o está inactiva', p_station_id;
  END IF;

  -- 2) Validar usuario activo + autorización estación
  PERFORM 1
  FROM clinicqueue.users u
  WHERE u.user_id = p_user_id
    AND u.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % no existe o está inactivo', p_user_id;
  END IF;

  PERFORM 1
  FROM clinicqueue.station_users su
  WHERE su.station_id = p_station_id
    AND su.user_id = p_user_id
    AND su.is_enabled = true
    AND (su.valid_from IS NULL OR su.valid_from <= v_now)
    AND (su.valid_to   IS NULL OR su.valid_to   >  v_now);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % no está autorizado para operar Station %', p_user_id, p_station_id;
  END IF;

  -- 3) Leer ticket y validar que fue llamado por esta estación (lock)
  SELECT t.status, t.station_id, t.module_id
    INTO v_status, v_station_from_ticket, v_module_from_ticket
  FROM clinicqueue.tickets t
  WHERE t.ticket_id = p_ticket_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ticket % no existe', p_ticket_id;
  END IF;

  IF v_status <> 'LLAMADO' THEN
    RAISE EXCEPTION 'Solo se puede re-llamar un ticket en estado LLAMADO. Estado actual: %', v_status;
  END IF;

  IF v_station_from_ticket IS DISTINCT FROM p_station_id THEN
    RAISE EXCEPTION 'Ticket % fue llamado por otra estación (%). No puedes re-llamar desde (%)',
      p_ticket_id, v_station_from_ticket, p_station_id;
  END IF;

  -- 4) Re-llamar: solo refrescar called_at y called_by (sin cambiar estado)
  UPDATE clinicqueue.tickets t
  SET called_at = v_now,
      called_by = p_user_id
  WHERE t.ticket_id = p_ticket_id
  RETURNING
    t.ticket_id, t.code, t.prefix, t.tck_number, t.station_id, t.module_id, t.status, t.called_at
  INTO
    out_ticket_id, out_code, out_prefix, out_tck_number, out_station_id, out_module_id, out_status, out_called_at;

  -- 5) Evento
  INSERT INTO clinicqueue.ticket_events(
    ticket_id, event_type, from_status, to_status, station_id, module_id, user_id, event_at, details
  )
  VALUES (
    out_ticket_id,
    'RECALLED',
    'LLAMADO',
    'LLAMADO',
    out_station_id,
    out_module_id,
    p_user_id,
    v_now,
    jsonb_build_object('reason', p_reason)
  );

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.recall_ticket(p_ticket_id bigint, p_station_id bigint, p_user_id bigint, p_reason text) OWNER TO postgres;

--
-- TOC entry 698 (class 1255 OID 55630)
-- Name: remove_role_from_user(bigint, bigint); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.remove_role_from_user(p_user_id bigint, p_role_id bigint) RETURNS TABLE(out_user_id bigint, out_role_id bigint, out_removed boolean)
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM clinicqueue.user_roles ur
  WHERE ur.user_id = p_user_id
    AND ur.role_id = p_role_id;

  out_user_id := p_user_id;
  out_role_id := p_role_id;
  out_removed := (FOUND);

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.remove_role_from_user(p_user_id bigint, p_role_id bigint) OWNER TO postgres;

--
-- TOC entry 723 (class 1255 OID 55667)
-- Name: remove_station_from_board(bigint, bigint); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.remove_station_from_board(p_board_id bigint, p_station_id bigint) RETURNS TABLE(out_board_id bigint, out_station_id bigint, out_removed boolean)
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM clinicqueue.board_stations bs
  WHERE bs.board_id = p_board_id
    AND bs.station_id = p_station_id;

  out_board_id := p_board_id;
  out_station_id := p_station_id;
  out_removed := FOUND;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.remove_station_from_board(p_board_id bigint, p_station_id bigint) OWNER TO postgres;

--
-- TOC entry 707 (class 1255 OID 55639)
-- Name: remove_user_from_station(bigint, bigint); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.remove_user_from_station(p_station_id bigint, p_user_id bigint) RETURNS TABLE(out_station_id bigint, out_user_id bigint, out_removed boolean)
    LANGUAGE plpgsql
    AS $$
BEGIN
  DELETE FROM clinicqueue.station_users su
  WHERE su.station_id = p_station_id
    AND su.user_id = p_user_id;

  out_station_id := p_station_id;
  out_user_id := p_user_id;
  out_removed := FOUND;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.remove_user_from_station(p_station_id bigint, p_user_id bigint) OWNER TO postgres;

--
-- TOC entry 680 (class 1255 OID 55596)
-- Name: requeue_ticket(bigint, bigint, bigint, text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.requeue_ticket(p_ticket_id bigint, p_station_id bigint, p_user_id bigint, p_reason text DEFAULT NULL::text) RETURNS TABLE(out_ticket_id bigint, out_code text, out_prefix text, out_tck_number integer, out_status clinicqueue.ticket_status)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_now timestamptz := now();
  v_from_status clinicqueue.ticket_status;
BEGIN
  -- 1) Validar estación activa
  PERFORM 1
  FROM clinicqueue.stations s
  WHERE s.station_id = p_station_id
    AND s.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Station % no existe o está inactiva', p_station_id;
  END IF;

  -- 2) Validar usuario activo + autorización
  PERFORM 1
  FROM clinicqueue.users u
  WHERE u.user_id = p_user_id
    AND u.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % no existe o está inactivo', p_user_id;
  END IF;

  PERFORM 1
  FROM clinicqueue.station_users su
  WHERE su.station_id = p_station_id
    AND su.user_id = p_user_id
    AND su.is_enabled = true
    AND (su.valid_from IS NULL OR su.valid_from <= v_now)
    AND (su.valid_to   IS NULL OR su.valid_to   >  v_now);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % no está autorizado para operar Station %', p_user_id, p_station_id;
  END IF;

  -- 3) Leer estado actual (lock)
  SELECT t.status
    INTO v_from_status
  FROM clinicqueue.tickets t
  WHERE t.ticket_id = p_ticket_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ticket % no existe', p_ticket_id;
  END IF;

  IF v_from_status NOT IN ('LLAMADO','EN_ATENCION') THEN
    RAISE EXCEPTION 'Ticket % no puede devolverse a cola desde estado %', p_ticket_id, v_from_status;
  END IF;

  -- 4) Actualizar: devolver a cola y liberar asignaciones
  UPDATE clinicqueue.tickets t
  SET status     = 'EN_COLA',
      station_id = NULL,
      module_id  = NULL,
      called_at  = NULL,
      called_by  = NULL,
      started_at = NULL,
      started_by = NULL
  WHERE t.ticket_id = p_ticket_id
  RETURNING t.ticket_id, t.code, t.prefix, t.tck_number, t.status
  INTO out_ticket_id, out_code, out_prefix, out_tck_number, out_status;

  -- 5) Evento
  INSERT INTO clinicqueue.ticket_events(
    ticket_id, event_type, from_status, to_status, station_id, module_id, user_id, event_at, details
  )
  VALUES (
    out_ticket_id,
    'TRANSFERRED',              -- reutilizamos este tipo para "devuelto a cola"
    v_from_status,
    'EN_COLA',
    p_station_id,
    NULL,
    p_user_id,
    v_now,
    jsonb_build_object(
      'action', 'REQUEUE',
      'reason', p_reason
    )
  );

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.requeue_ticket(p_ticket_id bigint, p_station_id bigint, p_user_id bigint, p_reason text) OWNER TO postgres;

--
-- TOC entry 719 (class 1255 OID 55663)
-- Name: set_display_board_status(bigint, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.set_display_board_status(p_board_id bigint, p_is_active boolean) RETURNS TABLE(out_board_id bigint, out_board_code text, out_is_active boolean, out_updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE clinicqueue.display_boards b
  SET is_active = p_is_active,
      updated_at = now()
  WHERE b.board_id = p_board_id
  RETURNING b.board_id, b.board_code, b.is_active, b.updated_at
  INTO out_board_id, out_board_code, out_is_active, out_updated_at;

  IF out_board_id IS NULL THEN
    RAISE EXCEPTION 'Display board % no existe', p_board_id;
  END IF;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.set_display_board_status(p_board_id bigint, p_is_active boolean) OWNER TO postgres;

--
-- TOC entry 715 (class 1255 OID 55659)
-- Name: set_module_status(bigint, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.set_module_status(p_module_id bigint, p_is_active boolean) RETURNS TABLE(out_module_id bigint, out_module_code text, out_is_active boolean, out_updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE clinicqueue.modules m
  SET is_active = p_is_active,
      updated_at = now()
  WHERE m.module_id = p_module_id
  RETURNING m.module_id, m.module_code, m.is_active, m.updated_at
  INTO out_module_id, out_module_code, out_is_active, out_updated_at;

  IF out_module_id IS NULL THEN
    RAISE EXCEPTION 'Module % no existe', p_module_id;
  END IF;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.set_module_status(p_module_id bigint, p_is_active boolean) OWNER TO postgres;

--
-- TOC entry 696 (class 1255 OID 55628)
-- Name: set_role_status(bigint, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.set_role_status(p_role_id bigint, p_is_active boolean) RETURNS TABLE(out_role_id bigint, out_role_code text, out_is_active boolean, out_updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE clinicqueue.roles r
  SET is_active = p_is_active,
      updated_at = now()
  WHERE r.role_id = p_role_id
  RETURNING r.role_id, r.role_code, r.is_active, r.updated_at
  INTO out_role_id, out_role_code, out_is_active, out_updated_at;

  IF out_role_id IS NULL THEN
    RAISE EXCEPTION 'Role % no existe', p_role_id;
  END IF;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.set_role_status(p_role_id bigint, p_is_active boolean) OWNER TO postgres;

--
-- TOC entry 704 (class 1255 OID 55636)
-- Name: set_station_module(bigint, bigint); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.set_station_module(p_station_id bigint, p_module_id bigint DEFAULT NULL::bigint) RETURNS TABLE(out_station_id bigint, out_station_code text, out_prefix text, out_module_id bigint, out_updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- si module_id no es NULL, validar que exista activo
  IF p_module_id IS NOT NULL THEN
    PERFORM 1 FROM clinicqueue.modules m WHERE m.module_id = p_module_id AND m.is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'module_id % no existe o está inactivo', p_module_id;
    END IF;
  END IF;

  UPDATE clinicqueue.stations s
  SET module_id = p_module_id,
      updated_at = now()
  WHERE s.station_id = p_station_id
  RETURNING s.station_id, s.station_code, s.prefix, s.module_id, s.updated_at
  INTO out_station_id, out_station_code, out_prefix, out_module_id, out_updated_at;

  IF out_station_id IS NULL THEN
    RAISE EXCEPTION 'Station % no existe', p_station_id;
  END IF;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.set_station_module(p_station_id bigint, p_module_id bigint) OWNER TO postgres;

--
-- TOC entry 702 (class 1255 OID 55634)
-- Name: set_station_status(bigint, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.set_station_status(p_station_id bigint, p_is_active boolean) RETURNS TABLE(out_station_id bigint, out_station_code text, out_is_active boolean, out_updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE clinicqueue.stations s
  SET is_active = p_is_active,
      updated_at = now()
  WHERE s.station_id = p_station_id
  RETURNING s.station_id, s.station_code, s.is_active, s.updated_at
  INTO out_station_id, out_station_code, out_is_active, out_updated_at;

  IF out_station_id IS NULL THEN
    RAISE EXCEPTION 'Station % no existe', p_station_id;
  END IF;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.set_station_status(p_station_id bigint, p_is_active boolean) OWNER TO postgres;

--
-- TOC entry 693 (class 1255 OID 55625)
-- Name: set_user_status(bigint, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.set_user_status(p_user_id bigint, p_is_active boolean) RETURNS TABLE(out_user_id bigint, out_username text, out_is_active boolean, out_updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE clinicqueue.users u
  SET is_active = p_is_active,
      updated_at = now()
  WHERE u.user_id = p_user_id
  RETURNING u.user_id, u.username, u.is_active, u.updated_at
  INTO out_user_id, out_username, out_is_active, out_updated_at;

  IF out_user_id IS NULL THEN
    RAISE EXCEPTION 'User % no existe', p_user_id;
  END IF;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.set_user_status(p_user_id bigint, p_is_active boolean) OWNER TO postgres;

--
-- TOC entry 685 (class 1255 OID 55598)
-- Name: start_ticket(bigint, bigint, bigint); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.start_ticket(p_ticket_id bigint, p_station_id bigint, p_user_id bigint) RETURNS TABLE(out_ticket_id bigint, out_code text, out_prefix text, out_tck_number integer, out_station_id bigint, out_module_id bigint, out_status clinicqueue.ticket_status, out_started_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_now timestamptz := now();
  v_status clinicqueue.ticket_status;
  v_station_from_ticket bigint;
  v_module_from_ticket bigint;
BEGIN
  -- 1) Validar estación activa
  PERFORM 1
  FROM clinicqueue.stations s
  WHERE s.station_id = p_station_id
    AND s.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Station % no existe o está inactiva', p_station_id;
  END IF;

  -- 2) Validar usuario activo + autorización estación
  PERFORM 1
  FROM clinicqueue.users u
  WHERE u.user_id = p_user_id
    AND u.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % no existe o está inactivo', p_user_id;
  END IF;

  PERFORM 1
  FROM clinicqueue.station_users su
  WHERE su.station_id = p_station_id
    AND su.user_id = p_user_id
    AND su.is_enabled = true
    AND (su.valid_from IS NULL OR su.valid_from <= v_now)
    AND (su.valid_to   IS NULL OR su.valid_to   >  v_now);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % no está autorizado para operar Station %', p_user_id, p_station_id;
  END IF;

  -- 3) Leer ticket y validar que fue llamado por esta estación (lock)
  SELECT t.status, t.station_id, t.module_id
    INTO v_status, v_station_from_ticket, v_module_from_ticket
  FROM clinicqueue.tickets t
  WHERE t.ticket_id = p_ticket_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ticket % no existe', p_ticket_id;
  END IF;

  IF v_status <> 'LLAMADO' THEN
    RAISE EXCEPTION 'Solo se puede iniciar un ticket en estado LLAMADO. Estado actual: %', v_status;
  END IF;

  IF v_station_from_ticket IS DISTINCT FROM p_station_id THEN
    RAISE EXCEPTION 'Ticket % fue llamado por otra estación (%). No puedes iniciarlo desde (%)',
      p_ticket_id, v_station_from_ticket, p_station_id;
  END IF;

  -- 4) Iniciar: LLAMADO -> EN_ATENCION
  UPDATE clinicqueue.tickets t
  SET status     = 'EN_ATENCION',
      started_at = v_now,
      started_by = p_user_id
  WHERE t.ticket_id = p_ticket_id
  RETURNING
    t.ticket_id, t.code, t.prefix, t.tck_number, t.station_id, t.module_id, t.status, t.started_at
  INTO
    out_ticket_id, out_code, out_prefix, out_tck_number, out_station_id, out_module_id, out_status, out_started_at;

  -- 5) Evento
  INSERT INTO clinicqueue.ticket_events(
    ticket_id, event_type, from_status, to_status, station_id, module_id, user_id, event_at, details
  )
  VALUES (
    out_ticket_id,
    'STARTED',
    'LLAMADO',
    'EN_ATENCION',
    out_station_id,
    out_module_id,
    p_user_id,
    v_now,
    jsonb_build_object('action', 'START')
  );

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.start_ticket(p_ticket_id bigint, p_station_id bigint, p_user_id bigint) OWNER TO postgres;

--
-- TOC entry 608 (class 1255 OID 55567)
-- Name: trg_display_boards_normalize(); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.trg_display_boards_normalize() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.board_code := upper(trim(NEW.board_code));
    NEW.board_name := trim(NEW.board_name);
    IF NEW.location IS NOT NULL THEN
        NEW.location := trim(NEW.location);
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION clinicqueue.trg_display_boards_normalize() OWNER TO postgres;

--
-- TOC entry 654 (class 1255 OID 55256)
-- Name: trg_modules_normalize(); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.trg_modules_normalize() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.prefix := upper(trim(NEW.prefix));
    NEW.module_code := upper(trim(NEW.module_code));
    NEW.updated_at := now();

    -- Validar que el módulo empiece con el prefijo
    IF left(NEW.module_code, 1) <> NEW.prefix THEN
        RAISE EXCEPTION
        'El module_code (%) no coincide con el prefix (%)',
        NEW.module_code, NEW.prefix;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION clinicqueue.trg_modules_normalize() OWNER TO postgres;

--
-- TOC entry 645 (class 1255 OID 55234)
-- Name: trg_queue_counters_norm(); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.trg_queue_counters_norm() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.prefix := upper(trim(NEW.prefix));
  NEW.counter_key := trim(NEW.counter_key);
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION clinicqueue.trg_queue_counters_norm() OWNER TO postgres;

--
-- TOC entry 644 (class 1255 OID 55216)
-- Name: trg_queue_settings_norm(); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.trg_queue_settings_norm() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.prefix := upper(trim(NEW.prefix));
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION clinicqueue.trg_queue_settings_norm() OWNER TO postgres;

--
-- TOC entry 672 (class 1255 OID 55318)
-- Name: trg_roles_normalize(); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.trg_roles_normalize() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.role_code := upper(trim(NEW.role_code));
    NEW.role_name := trim(NEW.role_name);
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION clinicqueue.trg_roles_normalize() OWNER TO postgres;

--
-- TOC entry 678 (class 1255 OID 55283)
-- Name: trg_stations_normalize(); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.trg_stations_normalize() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_mod_prefix text;
BEGIN
    NEW.station_code := upper(trim(NEW.station_code));
    NEW.prefix := upper(trim(NEW.prefix));
    NEW.updated_at := now();

    -- Si hay módulo, validar que el módulo pertenezca al mismo prefijo
    IF NEW.module_id IS NOT NULL THEN
        SELECT m.prefix INTO v_mod_prefix
        FROM clinicqueue.modules m
        WHERE m.module_id = NEW.module_id
          AND m.is_active = true;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'module_id % no existe o está inactivo', NEW.module_id;
        END IF;

        IF upper(v_mod_prefix) <> NEW.prefix THEN
            RAISE EXCEPTION
              'Inconsistencia: station.prefix (%) != module.prefix (%)',
              NEW.prefix, v_mod_prefix;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION clinicqueue.trg_stations_normalize() OWNER TO postgres;

--
-- TOC entry 609 (class 1255 OID 55491)
-- Name: trg_ticket_events_validate(); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.trg_ticket_events_validate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- CREATED: nace en un estado, from_status puede ser NULL
  IF NEW.event_type = 'CREATED' THEN
    IF NEW.to_status IS NULL THEN
      RAISE EXCEPTION 'to_status es requerido para event_type CREATED';
    END IF;
    RETURN NEW;
  END IF;

  -- Eventos que representan transición de estado (requieren from y to y deben cambiar)
  IF NEW.event_type IN ('CALLED','STARTED','FINISHED','NO_SHOW','CANCELLED','TRANSFERRED') THEN
    IF NEW.from_status IS NULL OR NEW.to_status IS NULL THEN
      RAISE EXCEPTION 'from_status y to_status son requeridos para event_type %', NEW.event_type;
    END IF;

    IF NEW.from_status = NEW.to_status THEN
      RAISE EXCEPTION 'from_status y to_status no pueden ser iguales (%) para event_type %',
        NEW.to_status, NEW.event_type;
    END IF;

    RETURN NEW;
  END IF;

  -- Eventos informativos: RECALLED / NOTE_ADDED (permiten from=to o NULL)
  RETURN NEW;
END;
$$;


ALTER FUNCTION clinicqueue.trg_ticket_events_validate() OWNER TO postgres;

--
-- TOC entry 607 (class 1255 OID 55547)
-- Name: trg_ticket_transfers_validate(); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.trg_ticket_transfers_validate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_from_mod_prefix text;
    v_to_mod_prefix   text;
BEGIN
    IF NEW.from_prefix IS NOT NULL THEN
        NEW.from_prefix := upper(trim(NEW.from_prefix));
    END IF;

    NEW.to_prefix := upper(trim(NEW.to_prefix));

    -- Si se especifica módulo origen, validar que pertenezca a from_prefix (si viene)
    IF NEW.from_module_id IS NOT NULL AND NEW.from_prefix IS NOT NULL THEN
        SELECT m.prefix INTO v_from_mod_prefix
        FROM clinicqueue.modules m
        WHERE m.module_id = NEW.from_module_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'from_module_id % no existe', NEW.from_module_id;
        END IF;

        IF upper(v_from_mod_prefix) <> NEW.from_prefix THEN
            RAISE EXCEPTION 'from_module_id pertenece a % pero from_prefix es %', v_from_mod_prefix, NEW.from_prefix;
        END IF;
    END IF;

    -- Si se especifica módulo destino, validar que pertenezca a to_prefix
    IF NEW.to_module_id IS NOT NULL THEN
        SELECT m.prefix INTO v_to_mod_prefix
        FROM clinicqueue.modules m
        WHERE m.module_id = NEW.to_module_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'to_module_id % no existe', NEW.to_module_id;
        END IF;

        IF upper(v_to_mod_prefix) <> NEW.to_prefix THEN
            RAISE EXCEPTION 'to_module_id pertenece a % pero to_prefix es %', v_to_mod_prefix, NEW.to_prefix;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION clinicqueue.trg_ticket_transfers_validate() OWNER TO postgres;

--
-- TOC entry 679 (class 1255 OID 55368)
-- Name: trg_tickets_normalize(); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.trg_tickets_normalize() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.prefix := upper(trim(NEW.prefix));

    -- Asegura 2 dígitos siempre
    IF NEW.code IS NULL OR length(trim(NEW.code)) = 0 THEN
        NEW.code := NEW.prefix || lpad(NEW.number::text, 2, '0');
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION clinicqueue.trg_tickets_normalize() OWNER TO postgres;

--
-- TOC entry 671 (class 1255 OID 55302)
-- Name: trg_users_normalize(); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.trg_users_normalize() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.username := lower(trim(NEW.username));
    IF NEW.email IS NOT NULL THEN
        NEW.email := lower(trim(NEW.email));
    END IF;

    NEW.display_name := trim(NEW.display_name);
    NEW.updated_at := now();

    RETURN NEW;
END;
$$;


ALTER FUNCTION clinicqueue.trg_users_normalize() OWNER TO postgres;

--
-- TOC entry 688 (class 1255 OID 55837)
-- Name: trg_users_sync_status(); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.trg_users_sync_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.status_code IS NOT NULL THEN
        NEW.is_active := (NEW.status_code = 'ACTIVE');
    END IF;

    NEW.updated_at := now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION clinicqueue.trg_users_sync_status() OWNER TO postgres;

--
-- TOC entry 722 (class 1255 OID 55666)
-- Name: update_board_station(bigint, bigint, integer, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.update_board_station(p_board_id bigint, p_station_id bigint, p_display_order integer DEFAULT NULL::integer, p_is_enabled boolean DEFAULT NULL::boolean) RETURNS TABLE(out_board_id bigint, out_station_id bigint, out_display_order integer, out_is_enabled boolean, out_created_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF p_display_order IS NOT NULL AND p_display_order < 1 THEN
    RAISE EXCEPTION 'display_order debe ser >= 1';
  END IF;

  UPDATE clinicqueue.board_stations bs
  SET
    display_order = COALESCE(p_display_order, bs.display_order),
    is_enabled    = COALESCE(p_is_enabled, bs.is_enabled)
  WHERE bs.board_id = p_board_id
    AND bs.station_id = p_station_id
  RETURNING bs.board_id, bs.station_id, bs.display_order, bs.is_enabled, bs.created_at
  INTO out_board_id, out_station_id, out_display_order, out_is_enabled, out_created_at;

  IF out_board_id IS NULL THEN
    RAISE EXCEPTION 'No existe asignación board_id=% station_id=%', p_board_id, p_station_id;
  END IF;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.update_board_station(p_board_id bigint, p_station_id bigint, p_display_order integer, p_is_enabled boolean) OWNER TO postgres;

--
-- TOC entry 718 (class 1255 OID 55662)
-- Name: update_display_board(bigint, text, text, text, boolean, integer, boolean, boolean, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.update_display_board(p_board_id bigint, p_board_code text DEFAULT NULL::text, p_board_name text DEFAULT NULL::text, p_location text DEFAULT NULL::text, p_show_last_called boolean DEFAULT NULL::boolean, p_show_last_in_service integer DEFAULT NULL::integer, p_show_waiting_count boolean DEFAULT NULL::boolean, p_sound_enabled_override boolean DEFAULT NULL::boolean, p_set_sound_override_null boolean DEFAULT false) RETURNS TABLE(out_board_id bigint, out_board_code text, out_board_name text, out_location text, out_show_last_called boolean, out_show_last_in_service integer, out_show_waiting_count boolean, out_sound_enabled_override boolean, out_is_active boolean, out_updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_code text;
  v_sound_override boolean;
BEGIN
  IF p_board_code IS NOT NULL THEN
    v_code := upper(trim(p_board_code));
    IF length(v_code) < 3 THEN
      RAISE EXCEPTION 'board_code inválido: %', p_board_code;
    END IF;
  END IF;

  IF p_show_last_in_service IS NOT NULL AND p_show_last_in_service < 0 THEN
    RAISE EXCEPTION 'show_last_in_service debe ser >= 0';
  END IF;

  -- manejar override nullable de forma explícita
  IF p_set_sound_override_null THEN
    v_sound_override := NULL;
  ELSE
    v_sound_override := p_sound_enabled_override; -- puede ser NULL (significa "no tocar" en el UPDATE con COALESCE)
  END IF;

  UPDATE clinicqueue.display_boards b
  SET
    board_code = COALESCE(v_code, b.board_code),
    board_name = COALESCE(
      CASE WHEN p_board_name IS NULL THEN NULL ELSE trim(p_board_name) END,
      b.board_name
    ),
    location = COALESCE(
      CASE
        WHEN p_location IS NULL THEN NULL
        WHEN length(trim(p_location))=0 THEN NULL
        ELSE trim(p_location)
      END,
      b.location
    ),
    show_last_called = COALESCE(p_show_last_called, b.show_last_called),
    show_last_in_service = COALESCE(p_show_last_in_service, b.show_last_in_service),
    show_waiting_count = COALESCE(p_show_waiting_count, b.show_waiting_count),
    sound_enabled_override = CASE
      WHEN p_set_sound_override_null THEN NULL
      WHEN p_sound_enabled_override IS NULL THEN b.sound_enabled_override
      ELSE p_sound_enabled_override
    END,
    updated_at = now()
  WHERE b.board_id = p_board_id
  RETURNING
    b.board_id, b.board_code, b.board_name, b.location,
    b.show_last_called, b.show_last_in_service, b.show_waiting_count,
    b.sound_enabled_override, b.is_active, b.updated_at
  INTO
    out_board_id, out_board_code, out_board_name, out_location,
    out_show_last_called, out_show_last_in_service, out_show_waiting_count,
    out_sound_enabled_override, out_is_active, out_updated_at;

  IF out_board_id IS NULL THEN
    RAISE EXCEPTION 'Display board % no existe', p_board_id;
  END IF;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.update_display_board(p_board_id bigint, p_board_code text, p_board_name text, p_location text, p_show_last_called boolean, p_show_last_in_service integer, p_show_waiting_count boolean, p_sound_enabled_override boolean, p_set_sound_override_null boolean) OWNER TO postgres;

--
-- TOC entry 714 (class 1255 OID 55658)
-- Name: update_module(bigint, text, text, text, integer); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.update_module(p_module_id bigint, p_prefix text DEFAULT NULL::text, p_module_code text DEFAULT NULL::text, p_module_name text DEFAULT NULL::text, p_display_order integer DEFAULT NULL::integer) RETURNS TABLE(out_module_id bigint, out_prefix text, out_module_code text, out_module_name text, out_display_order integer, out_is_active boolean, out_updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_prefix text;
  v_code text;
BEGIN
  -- Prefijo (si viene)
  IF p_prefix IS NOT NULL THEN
    v_prefix := upper(trim(p_prefix));
    PERFORM 1 FROM clinicqueue.queue_settings qs WHERE qs.prefix = v_prefix;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Prefijo % no existe en clinicqueue.queue_settings', v_prefix;
    END IF;
  END IF;

  -- Module code (si viene)
  IF p_module_code IS NOT NULL THEN
    v_code := upper(trim(p_module_code));
  END IF;

  IF p_display_order IS NOT NULL AND p_display_order < 1 THEN
    RAISE EXCEPTION 'display_order debe ser >= 1';
  END IF;

  UPDATE clinicqueue.modules m
  SET
    prefix = COALESCE(v_prefix, m.prefix),
    module_code = COALESCE(v_code, m.module_code),
    module_name = COALESCE(
      CASE WHEN p_module_name IS NULL THEN NULL ELSE trim(p_module_name) END,
      m.module_name
    ),
    display_order = COALESCE(p_display_order, m.display_order),
    updated_at = now()
  WHERE m.module_id = p_module_id
  RETURNING m.module_id, m.prefix, m.module_code, m.module_name, m.display_order, m.is_active, m.updated_at
  INTO out_module_id, out_prefix, out_module_code, out_module_name, out_display_order, out_is_active, out_updated_at;

  IF out_module_id IS NULL THEN
    RAISE EXCEPTION 'Module % no existe', p_module_id;
  END IF;

  -- Validación post-update: module_code debe coincidir con prefix
  IF out_module_code IS NOT NULL AND left(out_module_code, 1) <> out_prefix THEN
    RAISE EXCEPTION 'module_code % no coincide con prefix %', out_module_code, out_prefix;
  END IF;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.update_module(p_module_id bigint, p_prefix text, p_module_code text, p_module_name text, p_display_order integer) OWNER TO postgres;

--
-- TOC entry 710 (class 1255 OID 55646)
-- Name: update_queue_settings(text, text, integer, integer, integer, boolean, interval, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.update_queue_settings(p_prefix text, p_mode text DEFAULT NULL::text, p_min_number integer DEFAULT NULL::integer, p_max_number integer DEFAULT NULL::integer, p_max_active integer DEFAULT NULL::integer, p_allow_walkins boolean DEFAULT NULL::boolean, p_no_show_timeout interval DEFAULT NULL::interval, p_sound_enabled boolean DEFAULT NULL::boolean) RETURNS TABLE(out_prefix text, out_mode text, out_min_number integer, out_max_number integer, out_max_active integer, out_allow_walkins boolean, out_no_show_timeout interval, out_sound_enabled boolean, out_created_at timestamp with time zone, out_updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_prefix text := upper(trim(p_prefix));
  v_mode text;
  v_min int;
  v_max int;
BEGIN
  -- Cargar actuales
  SELECT qs.mode, qs.min_number, qs.max_number
    INTO v_mode, v_min, v_max
  FROM clinicqueue.queue_settings qs
  WHERE qs.prefix = v_prefix;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Queue settings para prefix % no existe', v_prefix;
  END IF;

  -- Mode nuevo
  IF p_mode IS NOT NULL THEN
    v_mode := upper(trim(p_mode));
    IF v_mode NOT IN ('DAILY_RESET','CONTINUOUS') THEN
      RAISE EXCEPTION 'mode inválido: %. Use DAILY_RESET o CONTINUOUS', p_mode;
    END IF;
  END IF;

  -- Rango (si viene)
  IF p_min_number IS NOT NULL THEN v_min := p_min_number; END IF;
  IF p_max_number IS NOT NULL THEN v_max := p_max_number; END IF;

  IF v_min < 1 OR v_max > 99 OR v_min >= v_max THEN
    RAISE EXCEPTION 'Rango inválido min=% max=%. Debe ser 1..99 y min < max', v_min, v_max;
  END IF;

  IF p_max_active IS NOT NULL AND p_max_active < 1 THEN
    RAISE EXCEPTION 'max_active debe ser NULL o >= 1. Recibido: %', p_max_active;
  END IF;

  IF p_no_show_timeout IS NOT NULL AND p_no_show_timeout <= interval '0 seconds' THEN
    RAISE EXCEPTION 'no_show_timeout debe ser > 0';
  END IF;

  UPDATE clinicqueue.queue_settings qs
  SET
    mode           = COALESCE(v_mode, qs.mode),
    min_number     = COALESCE(v_min, qs.min_number),
    max_number     = COALESCE(v_max, qs.max_number),
    max_active     = COALESCE(p_max_active, qs.max_active),
    allow_walkins  = COALESCE(p_allow_walkins, qs.allow_walkins),
    no_show_timeout= COALESCE(p_no_show_timeout, qs.no_show_timeout),
    sound_enabled  = COALESCE(p_sound_enabled, qs.sound_enabled),
    updated_at     = now()
  WHERE qs.prefix = v_prefix
  RETURNING
    qs.prefix, qs.mode, qs.min_number, qs.max_number, qs.max_active, qs.allow_walkins,
    qs.no_show_timeout, qs.sound_enabled, qs.created_at, qs.updated_at
  INTO
    out_prefix, out_mode, out_min_number, out_max_number, out_max_active, out_allow_walkins,
    out_no_show_timeout, out_sound_enabled, out_created_at, out_updated_at;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.update_queue_settings(p_prefix text, p_mode text, p_min_number integer, p_max_number integer, p_max_active integer, p_allow_walkins boolean, p_no_show_timeout interval, p_sound_enabled boolean) OWNER TO postgres;

--
-- TOC entry 695 (class 1255 OID 55627)
-- Name: update_role(bigint, text, text, text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.update_role(p_role_id bigint, p_role_code text DEFAULT NULL::text, p_role_name text DEFAULT NULL::text, p_description text DEFAULT NULL::text) RETURNS TABLE(out_role_id bigint, out_role_code text, out_role_name text, out_description text, out_is_active boolean, out_updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE clinicqueue.roles r
  SET
    role_code = COALESCE(
      CASE WHEN p_role_code IS NULL THEN NULL ELSE upper(trim(p_role_code)) END,
      r.role_code
    ),
    role_name = COALESCE(
      CASE WHEN p_role_name IS NULL THEN NULL ELSE trim(p_role_name) END,
      r.role_name
    ),
    description = COALESCE(
      CASE
        WHEN p_description IS NULL THEN NULL
        WHEN length(trim(p_description))=0 THEN NULL
        ELSE trim(p_description)
      END,
      r.description
    ),
    updated_at = now()
  WHERE r.role_id = p_role_id
  RETURNING r.role_id, r.role_code, r.role_name, r.description, r.is_active, r.updated_at
  INTO out_role_id, out_role_code, out_role_name, out_description, out_is_active, out_updated_at;

  IF out_role_id IS NULL THEN
    RAISE EXCEPTION 'Role % no existe', p_role_id;
  END IF;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.update_role(p_role_id bigint, p_role_code text, p_role_name text, p_description text) OWNER TO postgres;

--
-- TOC entry 701 (class 1255 OID 55633)
-- Name: update_station(bigint, text, text, text, bigint); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.update_station(p_station_id bigint, p_station_code text DEFAULT NULL::text, p_station_name text DEFAULT NULL::text, p_prefix text DEFAULT NULL::text, p_module_id bigint DEFAULT NULL::bigint) RETURNS TABLE(out_station_id bigint, out_station_code text, out_station_name text, out_prefix text, out_module_id bigint, out_is_active boolean, out_updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_prefix text;
BEGIN
  -- Si quieren cambiar prefijo, validar que exista
  IF p_prefix IS NOT NULL THEN
    v_prefix := upper(trim(p_prefix));
    PERFORM 1 FROM clinicqueue.queue_settings qs WHERE qs.prefix = v_prefix;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Prefijo % no existe en clinicqueue.queue_settings', v_prefix;
    END IF;
  END IF;

  -- Si module_id viene (y no es NULL), validar exista y esté activo
  IF p_module_id IS NOT NULL THEN
    PERFORM 1 FROM clinicqueue.modules m WHERE m.module_id = p_module_id AND m.is_active = true;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'module_id % no existe o está inactivo', p_module_id;
    END IF;
  END IF;

  UPDATE clinicqueue.stations s
  SET
    station_code = COALESCE(
      CASE WHEN p_station_code IS NULL THEN NULL ELSE upper(trim(p_station_code)) END,
      s.station_code
    ),
    station_name = COALESCE(
      CASE WHEN p_station_name IS NULL THEN NULL ELSE trim(p_station_name) END,
      s.station_name
    ),
    prefix = COALESCE(
      CASE WHEN p_prefix IS NULL THEN NULL ELSE upper(trim(p_prefix)) END,
      s.prefix
    ),
    module_id = COALESCE(p_module_id, s.module_id),
    updated_at = now()
  WHERE s.station_id = p_station_id
  RETURNING s.station_id, s.station_code, s.station_name, s.prefix, s.module_id, s.is_active, s.updated_at
  INTO out_station_id, out_station_code, out_station_name, out_prefix, out_module_id, out_is_active, out_updated_at;

  IF out_station_id IS NULL THEN
    RAISE EXCEPTION 'Station % no existe', p_station_id;
  END IF;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.update_station(p_station_id bigint, p_station_code text, p_station_name text, p_prefix text, p_module_id bigint) OWNER TO postgres;

--
-- TOC entry 706 (class 1255 OID 55638)
-- Name: update_station_user(bigint, bigint, boolean, timestamp with time zone, timestamp with time zone, boolean, boolean); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.update_station_user(p_station_id bigint, p_user_id bigint, p_is_enabled boolean DEFAULT NULL::boolean, p_valid_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_valid_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_set_valid_from_null boolean DEFAULT false, p_set_valid_to_null boolean DEFAULT false) RETURNS TABLE(out_station_id bigint, out_user_id bigint, out_is_enabled boolean, out_valid_from timestamp with time zone, out_valid_to timestamp with time zone, out_assigned_at timestamp with time zone, out_assigned_by bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_valid_from timestamptz;
  v_valid_to timestamptz;
BEGIN
  -- Verificar que exista asignación
  PERFORM 1
  FROM clinicqueue.station_users su
  WHERE su.station_id=p_station_id AND su.user_id=p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No existe asignación station_id=% user_id=%', p_station_id, p_user_id;
  END IF;

  -- Computar ventana resultante para validar coherencia
  SELECT
    CASE
      WHEN p_set_valid_from_null THEN NULL
      WHEN p_valid_from IS NOT NULL THEN p_valid_from
      ELSE su.valid_from
    END,
    CASE
      WHEN p_set_valid_to_null THEN NULL
      WHEN p_valid_to IS NOT NULL THEN p_valid_to
      ELSE su.valid_to
    END
  INTO v_valid_from, v_valid_to
  FROM clinicqueue.station_users su
  WHERE su.station_id=p_station_id AND su.user_id=p_user_id;

  IF v_valid_from IS NOT NULL AND v_valid_to IS NOT NULL AND v_valid_to <= v_valid_from THEN
    RAISE EXCEPTION 'valid_to (%) debe ser mayor que valid_from (%)', v_valid_to, v_valid_from;
  END IF;

  UPDATE clinicqueue.station_users su
  SET
    is_enabled = COALESCE(p_is_enabled, su.is_enabled),
    valid_from = v_valid_from,
    valid_to   = v_valid_to
  WHERE su.station_id=p_station_id AND su.user_id=p_user_id
  RETURNING su.station_id, su.user_id, su.is_enabled, su.valid_from, su.valid_to, su.assigned_at, su.assigned_by
  INTO out_station_id, out_user_id, out_is_enabled, out_valid_from, out_valid_to, out_assigned_at, out_assigned_by;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.update_station_user(p_station_id bigint, p_user_id bigint, p_is_enabled boolean, p_valid_from timestamp with time zone, p_valid_to timestamp with time zone, p_set_valid_from_null boolean, p_set_valid_to_null boolean) OWNER TO postgres;

--
-- TOC entry 692 (class 1255 OID 55624)
-- Name: update_user(bigint, text, text, text, text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.update_user(p_user_id bigint, p_username text DEFAULT NULL::text, p_display_name text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text) RETURNS TABLE(out_user_id bigint, out_username text, out_display_name text, out_email text, out_phone text, out_is_active boolean, out_updated_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE clinicqueue.users u
  SET
    username = COALESCE(
      CASE WHEN p_username IS NULL THEN NULL ELSE lower(trim(p_username)) END,
      u.username
    ),
    display_name = COALESCE(
      CASE WHEN p_display_name IS NULL THEN NULL ELSE trim(p_display_name) END,
      u.display_name
    ),
    email = COALESCE(
      CASE
        WHEN p_email IS NULL THEN NULL
        WHEN length(trim(p_email)) = 0 THEN NULL
        ELSE lower(trim(p_email))
      END,
      u.email
    ),
    phone = COALESCE(
      CASE
        WHEN p_phone IS NULL THEN NULL
        WHEN length(trim(p_phone)) = 0 THEN NULL
        ELSE trim(p_phone)
      END,
      u.phone
    ),
    updated_at = now()
  WHERE u.user_id = p_user_id
  RETURNING
    u.user_id, u.username, u.display_name, u.email, u.phone, u.is_active, u.updated_at
  INTO
    out_user_id, out_username, out_display_name, out_email, out_phone, out_is_active, out_updated_at;

  IF out_user_id IS NULL THEN
    RAISE EXCEPTION 'User % no existe', p_user_id;
  END IF;

  RETURN NEXT;
END;
$$;


ALTER FUNCTION clinicqueue.update_user(p_user_id bigint, p_username text, p_display_name text, p_email text, p_phone text) OWNER TO postgres;

--
-- TOC entry 712 (class 1255 OID 55622)
-- Name: xyz_get_board_snapshot(text); Type: FUNCTION; Schema: clinicqueue; Owner: postgres
--

CREATE FUNCTION clinicqueue.xyz_get_board_snapshot(p_board_code text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_code text := upper(trim(p_board_code));
  v_now_calling jsonb;
  v_in_service jsonb;
  v_waiting jsonb;
BEGIN
  -- now_calling: 1 ticket LLAMADO por estación (si existe)
  WITH ranked AS (
    SELECT
      s.station_code,
      s.station_name,
      m.module_code,
      t.ticket_id,
      t.code AS ticket_code,
      t.called_at,
      row_number() OVER (PARTITION BY s.station_id ORDER BY t.called_at DESC, t.ticket_id DESC) AS rn
    FROM clinicqueue.display_boards b
    JOIN clinicqueue.board_stations bs ON bs.board_id = b.board_id AND bs.is_enabled = true
    JOIN clinicqueue.stations s ON s.station_id = bs.station_id AND s.is_active = true
    LEFT JOIN clinicqueue.modules m ON m.module_id = s.module_id
    JOIN clinicqueue.tickets t ON t.station_id = s.station_id AND t.status = 'LLAMADO'
    WHERE b.board_code = v_code
      AND b.is_active = true
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.called_at DESC), '[]'::jsonb)
  INTO v_now_calling
  FROM (
    SELECT station_code, station_name, module_code, ticket_id, ticket_code, called_at
    FROM ranked
    WHERE rn = 1
  ) x;

  -- in_service: últimos 3 EN_ATENCION del board (configurable luego por display_boards.show_last_in_service)
  SELECT COALESCE(jsonb_agg(to_jsonb(y) ORDER BY y.started_at DESC), '[]'::jsonb)
  INTO v_in_service
  FROM (
    SELECT
      s.station_code,
      s.station_name,
      m.module_code,
      t.ticket_id,
      t.code AS ticket_code,
      t.started_at
    FROM clinicqueue.display_boards b
    JOIN clinicqueue.board_stations bs ON bs.board_id = b.board_id AND bs.is_enabled = true
    JOIN clinicqueue.stations s ON s.station_id = bs.station_id AND s.is_active = true
    LEFT JOIN clinicqueue.modules m ON m.module_id = s.module_id
    JOIN clinicqueue.tickets t ON t.station_id = s.station_id AND t.status = 'EN_ATENCION'
    WHERE b.board_code = v_code
      AND b.is_active = true
    ORDER BY t.started_at DESC NULLS LAST
    LIMIT 3
  ) y;

  -- waiting_counts por prefijo (solo prefijos presentes en estaciones del board)
  WITH bp AS (
    SELECT DISTINCT s.prefix
    FROM clinicqueue.display_boards b
    JOIN clinicqueue.board_stations bs ON bs.board_id = b.board_id AND bs.is_enabled = true
    JOIN clinicqueue.stations s ON s.station_id = bs.station_id AND s.is_active = true
    WHERE b.board_code = v_code
      AND b.is_active = true
  )
  SELECT COALESCE(jsonb_agg(to_jsonb(z) ORDER BY z.prefix), '[]'::jsonb)
  INTO v_waiting
  FROM (
    SELECT t.prefix, count(*)::bigint AS waiting_count
    FROM clinicqueue.tickets t
    JOIN bp ON bp.prefix = t.prefix
    WHERE t.status = 'EN_COLA'
    GROUP BY t.prefix
  ) z;

  RETURN jsonb_build_object(
    'board_code', v_code,
    'now_calling', v_now_calling,
    'in_service', v_in_service,
    'waiting_counts', v_waiting
  );
END;
$$;


ALTER FUNCTION clinicqueue.xyz_get_board_snapshot(p_board_code text) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 574 (class 1259 OID 55571)
-- Name: board_stations; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.board_stations (
    board_id bigint NOT NULL,
    station_id bigint NOT NULL,
    display_order integer DEFAULT 1 NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT board_stations_display_order_check CHECK ((display_order >= 1))
);


ALTER TABLE clinicqueue.board_stations OWNER TO postgres;

--
-- TOC entry 591 (class 1259 OID 55856)
-- Name: daily_close_runs; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.daily_close_runs (
    run_id bigint NOT NULL,
    run_mode text NOT NULL,
    operational_date date NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    executed_by bigint,
    tickets_closed integer DEFAULT 0 NOT NULL,
    notes text,
    CONSTRAINT daily_close_runs_mode_ck CHECK ((run_mode = ANY (ARRAY['MANUAL'::text, 'AUTO'::text])))
);


ALTER TABLE clinicqueue.daily_close_runs OWNER TO postgres;

--
-- TOC entry 590 (class 1259 OID 55855)
-- Name: daily_close_runs_run_id_seq; Type: SEQUENCE; Schema: clinicqueue; Owner: postgres
--

CREATE SEQUENCE clinicqueue.daily_close_runs_run_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE clinicqueue.daily_close_runs_run_id_seq OWNER TO postgres;

--
-- TOC entry 4545 (class 0 OID 0)
-- Dependencies: 590
-- Name: daily_close_runs_run_id_seq; Type: SEQUENCE OWNED BY; Schema: clinicqueue; Owner: postgres
--

ALTER SEQUENCE clinicqueue.daily_close_runs_run_id_seq OWNED BY clinicqueue.daily_close_runs.run_id;


--
-- TOC entry 573 (class 1259 OID 55550)
-- Name: display_boards; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.display_boards (
    board_id bigint NOT NULL,
    board_code text NOT NULL,
    board_name text NOT NULL,
    location text,
    show_last_called boolean DEFAULT true NOT NULL,
    show_last_in_service integer DEFAULT 3 NOT NULL,
    show_waiting_count boolean DEFAULT true NOT NULL,
    sound_enabled_override boolean,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT display_boards_show_last_in_service_check CHECK (((show_last_in_service >= 0) AND (show_last_in_service <= 20)))
);


ALTER TABLE clinicqueue.display_boards OWNER TO postgres;

--
-- TOC entry 572 (class 1259 OID 55549)
-- Name: display_boards_board_id_seq; Type: SEQUENCE; Schema: clinicqueue; Owner: postgres
--

CREATE SEQUENCE clinicqueue.display_boards_board_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE clinicqueue.display_boards_board_id_seq OWNER TO postgres;

--
-- TOC entry 4546 (class 0 OID 0)
-- Dependencies: 572
-- Name: display_boards_board_id_seq; Type: SEQUENCE OWNED BY; Schema: clinicqueue; Owner: postgres
--

ALTER SEQUENCE clinicqueue.display_boards_board_id_seq OWNED BY clinicqueue.display_boards.board_id;


--
-- TOC entry 585 (class 1259 OID 55775)
-- Name: kiosk_queues; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.kiosk_queues (
    kiosk_queue_id bigint NOT NULL,
    kiosk_id bigint NOT NULL,
    prefix text NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint
);


ALTER TABLE clinicqueue.kiosk_queues OWNER TO postgres;

--
-- TOC entry 584 (class 1259 OID 55774)
-- Name: kiosk_queues_kiosk_queue_id_seq; Type: SEQUENCE; Schema: clinicqueue; Owner: postgres
--

CREATE SEQUENCE clinicqueue.kiosk_queues_kiosk_queue_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE clinicqueue.kiosk_queues_kiosk_queue_id_seq OWNER TO postgres;

--
-- TOC entry 4547 (class 0 OID 0)
-- Dependencies: 584
-- Name: kiosk_queues_kiosk_queue_id_seq; Type: SEQUENCE OWNED BY; Schema: clinicqueue; Owner: postgres
--

ALTER SEQUENCE clinicqueue.kiosk_queues_kiosk_queue_id_seq OWNED BY clinicqueue.kiosk_queues.kiosk_queue_id;


--
-- TOC entry 583 (class 1259 OID 55737)
-- Name: kiosks; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.kiosks (
    kiosk_id bigint NOT NULL,
    kiosk_code text NOT NULL,
    kiosk_name text NOT NULL,
    user_id bigint NOT NULL,
    location_desc text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_by bigint
);


ALTER TABLE clinicqueue.kiosks OWNER TO postgres;

--
-- TOC entry 582 (class 1259 OID 55736)
-- Name: kiosks_kiosk_id_seq; Type: SEQUENCE; Schema: clinicqueue; Owner: postgres
--

CREATE SEQUENCE clinicqueue.kiosks_kiosk_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE clinicqueue.kiosks_kiosk_id_seq OWNER TO postgres;

--
-- TOC entry 4548 (class 0 OID 0)
-- Dependencies: 582
-- Name: kiosks_kiosk_id_seq; Type: SEQUENCE OWNED BY; Schema: clinicqueue; Owner: postgres
--

ALTER SEQUENCE clinicqueue.kiosks_kiosk_id_seq OWNED BY clinicqueue.kiosks.kiosk_id;


--
-- TOC entry 557 (class 1259 OID 55237)
-- Name: modules; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.modules (
    module_id bigint NOT NULL,
    module_code text NOT NULL,
    prefix text NOT NULL,
    module_name text NOT NULL,
    display_order integer DEFAULT 1 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE clinicqueue.modules OWNER TO postgres;

--
-- TOC entry 556 (class 1259 OID 55236)
-- Name: modules_module_id_seq; Type: SEQUENCE; Schema: clinicqueue; Owner: postgres
--

CREATE SEQUENCE clinicqueue.modules_module_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE clinicqueue.modules_module_id_seq OWNER TO postgres;

--
-- TOC entry 4549 (class 0 OID 0)
-- Dependencies: 556
-- Name: modules_module_id_seq; Type: SEQUENCE OWNED BY; Schema: clinicqueue; Owner: postgres
--

ALTER SEQUENCE clinicqueue.modules_module_id_seq OWNED BY clinicqueue.modules.module_id;


--
-- TOC entry 555 (class 1259 OID 55218)
-- Name: queue_counters; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.queue_counters (
    prefix text NOT NULL,
    counter_key text NOT NULL,
    last_number integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT queue_counters_last_number_check CHECK (((last_number >= 0) AND (last_number <= 99)))
);


ALTER TABLE clinicqueue.queue_counters OWNER TO postgres;

--
-- TOC entry 554 (class 1259 OID 55197)
-- Name: queue_settings; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.queue_settings (
    prefix text NOT NULL,
    mode text NOT NULL,
    min_number integer DEFAULT 1 NOT NULL,
    max_number integer DEFAULT 99 NOT NULL,
    max_active integer,
    allow_walkins boolean DEFAULT true NOT NULL,
    no_show_timeout interval DEFAULT '00:03:00'::interval NOT NULL,
    sound_enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    service_name text,
    icon text,
    auto_close_open_tickets boolean DEFAULT true NOT NULL,
    day_close_time time without time zone DEFAULT '05:00:00'::time without time zone NOT NULL,
    CONSTRAINT queue_settings_check CHECK (((max_number <= 99) AND (max_number > min_number))),
    CONSTRAINT queue_settings_max_active_check CHECK (((max_active IS NULL) OR (max_active > 0))),
    CONSTRAINT queue_settings_min_number_check CHECK ((min_number >= 1)),
    CONSTRAINT queue_settings_mode_check CHECK ((mode = ANY (ARRAY['DAILY_RESET'::text, 'CONTINUOUS'::text]))),
    CONSTRAINT queue_settings_no_show_timeout_check CHECK ((no_show_timeout >= '00:00:00'::interval))
);


ALTER TABLE clinicqueue.queue_settings OWNER TO postgres;

--
-- TOC entry 581 (class 1259 OID 55683)
-- Name: refresh_tokens; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.refresh_tokens (
    token_id bigint NOT NULL,
    user_id integer NOT NULL,
    token character varying(256) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    revoked boolean DEFAULT false NOT NULL,
    revoked_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE clinicqueue.refresh_tokens OWNER TO postgres;

--
-- TOC entry 580 (class 1259 OID 55682)
-- Name: refresh_tokens_token_id_seq; Type: SEQUENCE; Schema: clinicqueue; Owner: postgres
--

CREATE SEQUENCE clinicqueue.refresh_tokens_token_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE clinicqueue.refresh_tokens_token_id_seq OWNER TO postgres;

--
-- TOC entry 4550 (class 0 OID 0)
-- Dependencies: 580
-- Name: refresh_tokens_token_id_seq; Type: SEQUENCE OWNED BY; Schema: clinicqueue; Owner: postgres
--

ALTER SEQUENCE clinicqueue.refresh_tokens_token_id_seq OWNED BY clinicqueue.refresh_tokens.token_id;


--
-- TOC entry 563 (class 1259 OID 55305)
-- Name: roles; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.roles (
    role_id bigint NOT NULL,
    role_code text NOT NULL,
    role_name text NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE clinicqueue.roles OWNER TO postgres;

--
-- TOC entry 562 (class 1259 OID 55304)
-- Name: roles_role_id_seq; Type: SEQUENCE; Schema: clinicqueue; Owner: postgres
--

CREATE SEQUENCE clinicqueue.roles_role_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE clinicqueue.roles_role_id_seq OWNER TO postgres;

--
-- TOC entry 4551 (class 0 OID 0)
-- Dependencies: 562
-- Name: roles_role_id_seq; Type: SEQUENCE OWNED BY; Schema: clinicqueue; Owner: postgres
--

ALTER SEQUENCE clinicqueue.roles_role_id_seq OWNED BY clinicqueue.roles.role_id;


--
-- TOC entry 565 (class 1259 OID 55343)
-- Name: station_users; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.station_users (
    station_id bigint NOT NULL,
    user_id bigint NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL,
    valid_from timestamp with time zone,
    valid_to timestamp with time zone,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL,
    assigned_by bigint,
    CONSTRAINT ck_station_users_valid_window CHECK (((valid_from IS NULL) OR (valid_to IS NULL) OR (valid_to > valid_from)))
);


ALTER TABLE clinicqueue.station_users OWNER TO postgres;

--
-- TOC entry 559 (class 1259 OID 55259)
-- Name: stations; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.stations (
    station_id bigint NOT NULL,
    station_code text NOT NULL,
    station_name text NOT NULL,
    prefix text NOT NULL,
    module_id bigint,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE clinicqueue.stations OWNER TO postgres;

--
-- TOC entry 558 (class 1259 OID 55258)
-- Name: stations_station_id_seq; Type: SEQUENCE; Schema: clinicqueue; Owner: postgres
--

CREATE SEQUENCE clinicqueue.stations_station_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE clinicqueue.stations_station_id_seq OWNER TO postgres;

--
-- TOC entry 4552 (class 0 OID 0)
-- Dependencies: 558
-- Name: stations_station_id_seq; Type: SEQUENCE OWNED BY; Schema: clinicqueue; Owner: postgres
--

ALTER SEQUENCE clinicqueue.stations_station_id_seq OWNED BY clinicqueue.stations.station_id;


--
-- TOC entry 569 (class 1259 OID 55458)
-- Name: ticket_events; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.ticket_events (
    event_id bigint NOT NULL,
    ticket_id bigint NOT NULL,
    event_type clinicqueue.ticket_event_type NOT NULL,
    from_status clinicqueue.ticket_status,
    to_status clinicqueue.ticket_status,
    station_id bigint,
    module_id bigint,
    user_id bigint,
    event_at timestamp with time zone DEFAULT now() NOT NULL,
    details jsonb
);


ALTER TABLE clinicqueue.ticket_events OWNER TO postgres;

--
-- TOC entry 568 (class 1259 OID 55457)
-- Name: ticket_events_event_id_seq; Type: SEQUENCE; Schema: clinicqueue; Owner: postgres
--

CREATE SEQUENCE clinicqueue.ticket_events_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE clinicqueue.ticket_events_event_id_seq OWNER TO postgres;

--
-- TOC entry 4553 (class 0 OID 0)
-- Dependencies: 568
-- Name: ticket_events_event_id_seq; Type: SEQUENCE OWNED BY; Schema: clinicqueue; Owner: postgres
--

ALTER SEQUENCE clinicqueue.ticket_events_event_id_seq OWNED BY clinicqueue.ticket_events.event_id;


--
-- TOC entry 571 (class 1259 OID 55494)
-- Name: ticket_transfers; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.ticket_transfers (
    transfer_id bigint NOT NULL,
    ticket_id bigint NOT NULL,
    from_prefix text,
    from_module_id bigint,
    from_station_id bigint,
    to_prefix text NOT NULL,
    to_module_id bigint,
    to_station_id bigint,
    transferred_by bigint,
    transferred_at timestamp with time zone DEFAULT now() NOT NULL,
    reason text,
    details jsonb
);


ALTER TABLE clinicqueue.ticket_transfers OWNER TO postgres;

--
-- TOC entry 570 (class 1259 OID 55493)
-- Name: ticket_transfers_transfer_id_seq; Type: SEQUENCE; Schema: clinicqueue; Owner: postgres
--

CREATE SEQUENCE clinicqueue.ticket_transfers_transfer_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE clinicqueue.ticket_transfers_transfer_id_seq OWNER TO postgres;

--
-- TOC entry 4554 (class 0 OID 0)
-- Dependencies: 570
-- Name: ticket_transfers_transfer_id_seq; Type: SEQUENCE OWNED BY; Schema: clinicqueue; Owner: postgres
--

ALTER SEQUENCE clinicqueue.ticket_transfers_transfer_id_seq OWNED BY clinicqueue.ticket_transfers.transfer_id;


--
-- TOC entry 567 (class 1259 OID 55386)
-- Name: tickets; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.tickets (
    ticket_id bigint NOT NULL,
    prefix text NOT NULL,
    tck_number integer NOT NULL,
    code text NOT NULL,
    status clinicqueue.ticket_status DEFAULT 'EN_COLA'::clinicqueue.ticket_status NOT NULL,
    module_id bigint,
    station_id bigint,
    created_by bigint,
    called_by bigint,
    started_by bigint,
    ended_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    called_at timestamp with time zone,
    started_at timestamp with time zone,
    ended_at timestamp with time zone,
    ticket_date date DEFAULT CURRENT_DATE NOT NULL,
    notes text,
    issue_channel text DEFAULT 'DESK'::text NOT NULL,
    issued_by_kiosk_id bigint,
    CONSTRAINT tickets_issue_channel_check CHECK ((issue_channel = ANY (ARRAY['DESK'::text, 'KIOSK'::text, 'API'::text]))),
    CONSTRAINT tickets_number_check CHECK (((tck_number >= 1) AND (tck_number <= 99)))
);


ALTER TABLE clinicqueue.tickets OWNER TO postgres;

--
-- TOC entry 566 (class 1259 OID 55385)
-- Name: tickets_ticket_id_seq; Type: SEQUENCE; Schema: clinicqueue; Owner: postgres
--

CREATE SEQUENCE clinicqueue.tickets_ticket_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE clinicqueue.tickets_ticket_id_seq OWNER TO postgres;

--
-- TOC entry 4555 (class 0 OID 0)
-- Dependencies: 566
-- Name: tickets_ticket_id_seq; Type: SEQUENCE OWNED BY; Schema: clinicqueue; Owner: postgres
--

ALTER SEQUENCE clinicqueue.tickets_ticket_id_seq OWNED BY clinicqueue.tickets.ticket_id;


--
-- TOC entry 564 (class 1259 OID 55320)
-- Name: user_roles; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.user_roles (
    user_id bigint NOT NULL,
    role_id bigint NOT NULL,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL,
    assigned_by bigint
);


ALTER TABLE clinicqueue.user_roles OWNER TO postgres;

--
-- TOC entry 587 (class 1259 OID 55823)
-- Name: user_statuses; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.user_statuses (
    status_code text NOT NULL,
    status_name text NOT NULL,
    is_login_allowed boolean NOT NULL,
    sort_order integer NOT NULL,
    is_system boolean DEFAULT true NOT NULL
);


ALTER TABLE clinicqueue.user_statuses OWNER TO postgres;

--
-- TOC entry 561 (class 1259 OID 55286)
-- Name: users; Type: TABLE; Schema: clinicqueue; Owner: postgres
--

CREATE TABLE clinicqueue.users (
    user_id bigint NOT NULL,
    username text NOT NULL,
    display_name text NOT NULL,
    email text,
    phone text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_login_at timestamp with time zone,
    password_hash text NOT NULL,
    is_archived boolean DEFAULT false NOT NULL,
    archived_at timestamp with time zone,
    archived_by bigint,
    status_code text NOT NULL,
    CONSTRAINT users_archived_not_active_ck CHECK ((NOT ((is_archived = true) AND (is_active = true))))
);


ALTER TABLE clinicqueue.users OWNER TO postgres;

--
-- TOC entry 560 (class 1259 OID 55285)
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: clinicqueue; Owner: postgres
--

CREATE SEQUENCE clinicqueue.users_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE clinicqueue.users_user_id_seq OWNER TO postgres;

--
-- TOC entry 4556 (class 0 OID 0)
-- Dependencies: 560
-- Name: users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: clinicqueue; Owner: postgres
--

ALTER SEQUENCE clinicqueue.users_user_id_seq OWNED BY clinicqueue.users.user_id;


--
-- TOC entry 575 (class 1259 OID 55602)
-- Name: v_board_enabled_stations; Type: VIEW; Schema: clinicqueue; Owner: postgres
--

CREATE VIEW clinicqueue.v_board_enabled_stations AS
 SELECT b.board_id,
    b.board_code,
    b.board_name,
    bs.display_order,
    s.station_id,
    s.station_code,
    s.station_name,
    s.prefix,
    s.module_id,
    m.module_code,
    m.module_name
   FROM (((clinicqueue.display_boards b
     JOIN clinicqueue.board_stations bs ON (((bs.board_id = b.board_id) AND (bs.is_enabled = true))))
     JOIN clinicqueue.stations s ON (((s.station_id = bs.station_id) AND (s.is_active = true))))
     LEFT JOIN clinicqueue.modules m ON ((m.module_id = s.module_id)))
  WHERE (b.is_active = true);


ALTER VIEW clinicqueue.v_board_enabled_stations OWNER TO postgres;

--
-- TOC entry 577 (class 1259 OID 55612)
-- Name: v_board_in_service; Type: VIEW; Schema: clinicqueue; Owner: postgres
--

CREATE VIEW clinicqueue.v_board_in_service AS
 SELECT v.board_id,
    v.board_code,
    v.station_id,
    v.station_code,
    v.station_name,
    v.prefix,
    v.module_code,
    t.ticket_id,
    t.code AS ticket_code,
    t.tck_number,
    t.started_at
   FROM (clinicqueue.v_board_enabled_stations v
     JOIN clinicqueue.tickets t ON (((t.station_id = v.station_id) AND (t.status = 'EN_ATENCION'::clinicqueue.ticket_status))));


ALTER VIEW clinicqueue.v_board_in_service OWNER TO postgres;

--
-- TOC entry 576 (class 1259 OID 55607)
-- Name: v_board_now_calling; Type: VIEW; Schema: clinicqueue; Owner: postgres
--

CREATE VIEW clinicqueue.v_board_now_calling AS
 WITH ranked AS (
         SELECT v.board_id,
            v.board_code,
            v.station_id,
            v.station_code,
            v.station_name,
            v.prefix,
            v.module_code,
            t.ticket_id,
            t.code AS ticket_code,
            t.tck_number,
            t.called_at,
            row_number() OVER (PARTITION BY v.board_id, v.station_id ORDER BY t.called_at DESC, t.ticket_id DESC) AS rn
           FROM (clinicqueue.v_board_enabled_stations v
             JOIN clinicqueue.tickets t ON (((t.station_id = v.station_id) AND (t.status = 'LLAMADO'::clinicqueue.ticket_status))))
        )
 SELECT ranked.board_id,
    ranked.board_code,
    ranked.station_id,
    ranked.station_code,
    ranked.station_name,
    ranked.prefix,
    ranked.module_code,
    ranked.ticket_id,
    ranked.ticket_code,
    ranked.tck_number,
    ranked.called_at,
    ranked.rn
   FROM ranked
  WHERE (ranked.rn = 1);


ALTER VIEW clinicqueue.v_board_now_calling OWNER TO postgres;

--
-- TOC entry 586 (class 1259 OID 55810)
-- Name: v_kiosk_allowed_queues; Type: VIEW; Schema: clinicqueue; Owner: postgres
--

CREATE VIEW clinicqueue.v_kiosk_allowed_queues AS
 SELECT k.kiosk_id,
    k.kiosk_code,
    k.kiosk_name,
    k.user_id,
    k.location_desc,
    k.is_active AS kiosk_is_active,
    kq.kiosk_queue_id,
    kq.prefix,
    q.service_name,
    q.icon,
    q.mode,
    q.allow_walkins,
    q.sound_enabled,
    kq.is_enabled
   FROM ((clinicqueue.kiosks k
     JOIN clinicqueue.kiosk_queues kq ON ((kq.kiosk_id = k.kiosk_id)))
     JOIN clinicqueue.queue_settings q ON ((q.prefix = kq.prefix)))
  WHERE ((k.is_active = true) AND (kq.is_enabled = true));


ALTER VIEW clinicqueue.v_kiosk_allowed_queues OWNER TO postgres;

--
-- TOC entry 588 (class 1259 OID 55840)
-- Name: v_users; Type: VIEW; Schema: clinicqueue; Owner: postgres
--

CREATE VIEW clinicqueue.v_users AS
 SELECT u.user_id,
    u.username,
    u.display_name,
    u.email,
    u.phone,
    u.is_active,
    u.status_code,
    s.status_name,
    u.created_at,
    u.updated_at,
    u.last_login_at,
    COALESCE(jsonb_agg(DISTINCT jsonb_build_object('role_id', r.role_id, 'role_code', r.role_code, 'role_name', r.role_name)) FILTER (WHERE ((r.role_id IS NOT NULL) AND (r.is_active = true))), '[]'::jsonb) AS roles,
    COALESCE(array_agg(DISTINCT r.role_code) FILTER (WHERE ((r.role_code IS NOT NULL) AND (r.is_active = true))), ARRAY[]::text[]) AS role_codes
   FROM (((clinicqueue.users u
     LEFT JOIN clinicqueue.user_roles ur ON ((ur.user_id = u.user_id)))
     LEFT JOIN clinicqueue.roles r ON ((r.role_id = ur.role_id)))
     LEFT JOIN clinicqueue.user_statuses s ON ((s.status_code = u.status_code)))
  GROUP BY u.user_id, u.username, u.display_name, u.email, u.phone, u.is_active, u.status_code, s.status_name, u.created_at, u.updated_at, u.last_login_at;


ALTER VIEW clinicqueue.v_users OWNER TO postgres;

--
-- TOC entry 589 (class 1259 OID 55845)
-- Name: v_users_login; Type: VIEW; Schema: clinicqueue; Owner: postgres
--

CREATE VIEW clinicqueue.v_users_login AS
 SELECT u.user_id,
    u.username,
    u.display_name,
    u.email,
    u.phone,
    u.is_active,
    u.status_code,
    u.last_login_at,
    u.password_hash,
    COALESCE(array_agg(DISTINCT r.role_code) FILTER (WHERE ((r.role_code IS NOT NULL) AND (r.is_active = true))), ARRAY[]::text[]) AS role_codes
   FROM (((clinicqueue.users u
     JOIN clinicqueue.user_statuses s ON ((s.status_code = u.status_code)))
     LEFT JOIN clinicqueue.user_roles ur ON ((ur.user_id = u.user_id)))
     LEFT JOIN clinicqueue.roles r ON ((r.role_id = ur.role_id)))
  WHERE (s.is_login_allowed = true)
  GROUP BY u.user_id, u.username, u.display_name, u.email, u.phone, u.is_active, u.status_code, u.last_login_at, u.password_hash;


ALTER VIEW clinicqueue.v_users_login OWNER TO postgres;

--
-- TOC entry 579 (class 1259 OID 55677)
-- Name: v_users_login_old; Type: VIEW; Schema: clinicqueue; Owner: postgres
--

CREATE VIEW clinicqueue.v_users_login_old AS
 SELECT u.user_id,
    u.username,
    u.display_name,
    u.email,
    u.phone,
    u.is_active,
    u.last_login_at,
    u.password_hash,
    COALESCE(array_agg(DISTINCT r.role_code) FILTER (WHERE ((r.role_code IS NOT NULL) AND (r.is_active = true))), ARRAY[]::text[]) AS role_codes
   FROM ((clinicqueue.users u
     LEFT JOIN clinicqueue.user_roles ur ON ((ur.user_id = u.user_id)))
     LEFT JOIN clinicqueue.roles r ON ((r.role_id = ur.role_id)))
  GROUP BY u.user_id, u.username, u.display_name, u.email, u.phone, u.is_active, u.last_login_at, u.password_hash;


ALTER VIEW clinicqueue.v_users_login_old OWNER TO postgres;

--
-- TOC entry 578 (class 1259 OID 55672)
-- Name: v_users_old; Type: VIEW; Schema: clinicqueue; Owner: postgres
--

CREATE VIEW clinicqueue.v_users_old AS
 SELECT u.user_id,
    u.username,
    u.display_name,
    u.email,
    u.phone,
    u.is_active,
    u.created_at,
    u.updated_at,
    u.last_login_at,
    COALESCE(jsonb_agg(DISTINCT jsonb_build_object('role_id', r.role_id, 'role_code', r.role_code, 'role_name', r.role_name)) FILTER (WHERE ((r.role_id IS NOT NULL) AND (r.is_active = true))), '[]'::jsonb) AS roles,
    COALESCE(array_agg(DISTINCT r.role_code) FILTER (WHERE ((r.role_code IS NOT NULL) AND (r.is_active = true))), ARRAY[]::text[]) AS role_codes
   FROM ((clinicqueue.users u
     LEFT JOIN clinicqueue.user_roles ur ON ((ur.user_id = u.user_id)))
     LEFT JOIN clinicqueue.roles r ON ((r.role_id = ur.role_id)))
  GROUP BY u.user_id, u.username, u.display_name, u.email, u.phone, u.is_active, u.created_at, u.updated_at, u.last_login_at;


ALTER VIEW clinicqueue.v_users_old OWNER TO postgres;

--
-- TOC entry 4200 (class 2604 OID 55859)
-- Name: daily_close_runs run_id; Type: DEFAULT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.daily_close_runs ALTER COLUMN run_id SET DEFAULT nextval('clinicqueue.daily_close_runs_run_id_seq'::regclass);


--
-- TOC entry 4179 (class 2604 OID 55553)
-- Name: display_boards board_id; Type: DEFAULT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.display_boards ALTER COLUMN board_id SET DEFAULT nextval('clinicqueue.display_boards_board_id_seq'::regclass);


--
-- TOC entry 4196 (class 2604 OID 55778)
-- Name: kiosk_queues kiosk_queue_id; Type: DEFAULT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.kiosk_queues ALTER COLUMN kiosk_queue_id SET DEFAULT nextval('clinicqueue.kiosk_queues_kiosk_queue_id_seq'::regclass);


--
-- TOC entry 4192 (class 2604 OID 55740)
-- Name: kiosks kiosk_id; Type: DEFAULT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.kiosks ALTER COLUMN kiosk_id SET DEFAULT nextval('clinicqueue.kiosks_kiosk_id_seq'::regclass);


--
-- TOC entry 4149 (class 2604 OID 55240)
-- Name: modules module_id; Type: DEFAULT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.modules ALTER COLUMN module_id SET DEFAULT nextval('clinicqueue.modules_module_id_seq'::regclass);


--
-- TOC entry 4189 (class 2604 OID 55686)
-- Name: refresh_tokens token_id; Type: DEFAULT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.refresh_tokens ALTER COLUMN token_id SET DEFAULT nextval('clinicqueue.refresh_tokens_token_id_seq'::regclass);


--
-- TOC entry 4163 (class 2604 OID 55308)
-- Name: roles role_id; Type: DEFAULT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.roles ALTER COLUMN role_id SET DEFAULT nextval('clinicqueue.roles_role_id_seq'::regclass);


--
-- TOC entry 4154 (class 2604 OID 55262)
-- Name: stations station_id; Type: DEFAULT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.stations ALTER COLUMN station_id SET DEFAULT nextval('clinicqueue.stations_station_id_seq'::regclass);


--
-- TOC entry 4175 (class 2604 OID 55461)
-- Name: ticket_events event_id; Type: DEFAULT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_events ALTER COLUMN event_id SET DEFAULT nextval('clinicqueue.ticket_events_event_id_seq'::regclass);


--
-- TOC entry 4177 (class 2604 OID 55497)
-- Name: ticket_transfers transfer_id; Type: DEFAULT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_transfers ALTER COLUMN transfer_id SET DEFAULT nextval('clinicqueue.ticket_transfers_transfer_id_seq'::regclass);


--
-- TOC entry 4170 (class 2604 OID 55389)
-- Name: tickets ticket_id; Type: DEFAULT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.tickets ALTER COLUMN ticket_id SET DEFAULT nextval('clinicqueue.tickets_ticket_id_seq'::regclass);


--
-- TOC entry 4158 (class 2604 OID 55289)
-- Name: users user_id; Type: DEFAULT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.users ALTER COLUMN user_id SET DEFAULT nextval('clinicqueue.users_user_id_seq'::regclass);


--
-- TOC entry 4530 (class 0 OID 55571)
-- Dependencies: 574
-- Data for Name: board_stations; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.board_stations VALUES (1, 1, 1, true, '2026-02-28 11:44:39.779639-04');
INSERT INTO clinicqueue.board_stations VALUES (1, 2, 2, true, '2026-02-28 11:44:39.779639-04');
INSERT INTO clinicqueue.board_stations VALUES (1, 5, 3, true, '2026-02-28 11:44:39.779639-04');
INSERT INTO clinicqueue.board_stations VALUES (1, 8, 1, true, '2026-03-06 09:48:31.38354-04');


--
-- TOC entry 4539 (class 0 OID 55856)
-- Dependencies: 591
-- Data for Name: daily_close_runs; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.daily_close_runs VALUES (1, 'MANUAL', '2026-03-09', '2026-03-09 16:56:06.40165-04', '2026-03-09 16:56:06.40165-04', 1, 0, NULL);


--
-- TOC entry 4529 (class 0 OID 55550)
-- Dependencies: 573
-- Data for Name: display_boards; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.display_boards VALUES (2, 'TV_LAB', 'Pantalla Laboratorio', 'Área de Laboratorio', true, 3, true, true, true, '2026-02-28 11:43:26.909965-04', '2026-02-28 11:43:26.909965-04');
INSERT INTO clinicqueue.display_boards VALUES (3, 'TV_EMER', 'Pantalla Emergencia', 'Emergencia', true, 3, true, true, true, '2026-02-28 12:05:11.158541-04', '2026-02-28 12:05:11.158541-04');
INSERT INTO clinicqueue.display_boards VALUES (1, 'TV_LOBBY', 'Pantalla Lobby', 'Recepción', true, 3, true, true, true, '2026-02-28 11:43:26.909965-04', '2026-02-28 12:05:23.348497-04');
INSERT INTO clinicqueue.display_boards VALUES (4, 'TV_RADIO', 'Pantalla Radiografia', 'Recepción', true, 5, true, NULL, true, '2026-02-28 21:09:16.247582-04', '2026-02-28 21:09:51.418856-04');


--
-- TOC entry 4536 (class 0 OID 55775)
-- Dependencies: 585
-- Data for Name: kiosk_queues; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.kiosk_queues VALUES (1, 1, 'C', true, '2026-03-09 12:02:38.54569-04', NULL);
INSERT INTO clinicqueue.kiosk_queues VALUES (2, 1, 'L', true, '2026-03-09 12:02:38.548105-04', NULL);
INSERT INTO clinicqueue.kiosk_queues VALUES (3, 1, 'O', true, '2026-03-09 12:02:38.548618-04', NULL);
INSERT INTO clinicqueue.kiosk_queues VALUES (5, 2, 'E', true, '2026-03-09 15:37:14.883094-04', 1);


--
-- TOC entry 4534 (class 0 OID 55737)
-- Dependencies: 583
-- Data for Name: kiosks; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.kiosks VALUES (1, 'KSK-01', 'Terminal Lobby', 7, 'Lobby Principal', true, '2026-03-09 12:02:38.542355-04', '2026-03-09 12:02:38.542355-04', NULL, NULL);
INSERT INTO clinicqueue.kiosks VALUES (2, 'KSK-02', 'Terminal Emergencia', 10, 'Emergancia', true, '2026-03-09 15:36:02.471341-04', '2026-03-09 15:36:02.471341-04', 1, NULL);


--
-- TOC entry 4513 (class 0 OID 55237)
-- Dependencies: 557
-- Data for Name: modules; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.modules VALUES (7, 'E01', 'E', 'Emergencia', 1, true, '2026-02-27 00:24:17.166722-04', '2026-02-28 10:34:10.641143-04');
INSERT INTO clinicqueue.modules VALUES (6, 'L02', 'L', 'Laboratorio 2', 2, false, '2026-02-27 00:24:17.166722-04', '2026-03-06 11:22:44.932071-04');
INSERT INTO clinicqueue.modules VALUES (5, 'L01', 'L', 'Laboratorio', 1, true, '2026-02-27 00:24:17.166722-04', '2026-03-06 11:22:49.399825-04');
INSERT INTO clinicqueue.modules VALUES (3, 'P01', 'P', 'Psicología', 1, true, '2026-02-27 00:24:17.166722-04', '2026-03-06 11:23:02.889339-04');
INSERT INTO clinicqueue.modules VALUES (4, 'O01', 'O', 'Odontología', 1, true, '2026-02-27 00:24:17.166722-04', '2026-03-06 11:23:08.093209-04');
INSERT INTO clinicqueue.modules VALUES (1, 'C01', 'C', 'Consultorio 1', 1, true, '2026-02-27 00:24:17.166722-04', '2026-03-06 11:24:04.575771-04');
INSERT INTO clinicqueue.modules VALUES (2, 'C02', 'C', 'Consultorio 2', 2, true, '2026-02-27 00:24:17.166722-04', '2026-03-06 11:24:08.564392-04');
INSERT INTO clinicqueue.modules VALUES (8, 'C03', 'C', 'Consultorio 3', 1, true, '2026-03-06 09:51:58.553566-04', '2026-03-06 11:24:11.551579-04');


--
-- TOC entry 4511 (class 0 OID 55218)
-- Dependencies: 555
-- Data for Name: queue_counters; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.queue_counters VALUES ('C', 'GLOBAL', 12, '2026-02-27 00:21:23.100961-04');
INSERT INTO clinicqueue.queue_counters VALUES ('P', 'GLOBAL', 7, '2026-02-27 00:21:23.100961-04');
INSERT INTO clinicqueue.queue_counters VALUES ('O', 'GLOBAL', 55, '2026-02-27 00:21:23.100961-04');
INSERT INTO clinicqueue.queue_counters VALUES ('L', 'GLOBAL', 3, '2026-02-27 00:21:23.100961-04');
INSERT INTO clinicqueue.queue_counters VALUES ('C', '2026-02-27', 21, '2026-02-27 00:21:30.602775-04');
INSERT INTO clinicqueue.queue_counters VALUES ('P', '2026-02-27', 4, '2026-02-27 00:21:30.602775-04');
INSERT INTO clinicqueue.queue_counters VALUES ('O', '2026-02-27', 9, '2026-02-27 00:21:30.602775-04');
INSERT INTO clinicqueue.queue_counters VALUES ('L', '2026-02-27', 33, '2026-02-27 00:21:30.602775-04');
INSERT INTO clinicqueue.queue_counters VALUES ('C', '2026-02-26', 88, '2026-02-27 00:21:37.851632-04');
INSERT INTO clinicqueue.queue_counters VALUES ('P', '2026-02-26', 15, '2026-02-27 00:21:37.851632-04');
INSERT INTO clinicqueue.queue_counters VALUES ('O', '2026-02-26', 61, '2026-02-27 00:21:37.851632-04');
INSERT INTO clinicqueue.queue_counters VALUES ('L', '2026-02-26', 99, '2026-02-27 00:21:37.851632-04');
INSERT INTO clinicqueue.queue_counters VALUES ('L', '2026-03-06', 6, '2026-03-06 14:49:25.795523-04');
INSERT INTO clinicqueue.queue_counters VALUES ('O', '2026-03-06', 1, '2026-03-06 14:49:33.244293-04');
INSERT INTO clinicqueue.queue_counters VALUES ('P', '2026-03-06', 1, '2026-03-06 14:49:36.910413-04');
INSERT INTO clinicqueue.queue_counters VALUES ('L', '2026-02-28', 5, '2026-02-28 17:15:57.538926-04');
INSERT INTO clinicqueue.queue_counters VALUES ('C', '2026-03-06', 31, '2026-03-06 15:53:45.88168-04');
INSERT INTO clinicqueue.queue_counters VALUES ('C', '2026-02-28', 16, '2026-02-28 18:11:44.730346-04');
INSERT INTO clinicqueue.queue_counters VALUES ('C', '2026-03-09', 19, '2026-03-09 12:42:37.782728-04');
INSERT INTO clinicqueue.queue_counters VALUES ('O', '2026-03-09', 1, '2026-03-09 15:11:08.652226-04');
INSERT INTO clinicqueue.queue_counters VALUES ('L', '2026-03-09', 1, '2026-03-09 15:11:18.781866-04');
INSERT INTO clinicqueue.queue_counters VALUES ('E', 'GLOBAL', 4, '2026-03-09 15:37:28.371095-04');


--
-- TOC entry 4510 (class 0 OID 55197)
-- Dependencies: 554
-- Data for Name: queue_settings; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.queue_settings VALUES ('C', 'DAILY_RESET', 1, 99, 99, true, '00:03:00', true, '2026-02-27 00:13:34.321606-04', '2026-03-06 11:40:42.427222-04', 'Consultorio', '🩺', true, '05:00:00');
INSERT INTO clinicqueue.queue_settings VALUES ('L', 'DAILY_RESET', 1, 99, 99, true, '00:02:00', true, '2026-02-27 00:13:34.321606-04', '2026-03-06 11:40:42.429972-04', 'Laboratorio', '🔬', true, '05:00:00');
INSERT INTO clinicqueue.queue_settings VALUES ('P', 'DAILY_RESET', 1, 99, 99, true, '00:05:00', true, '2026-02-27 00:13:34.321606-04', '2026-03-06 11:40:42.430802-04', 'Psicología', '🧠', true, '05:00:00');
INSERT INTO clinicqueue.queue_settings VALUES ('O', 'DAILY_RESET', 1, 99, 99, true, '00:05:00', true, '2026-02-27 00:13:34.321606-04', '2026-03-06 11:40:42.43118-04', 'Odontología', '🦷', true, '05:00:00');
INSERT INTO clinicqueue.queue_settings VALUES ('PD', 'DAILY_RESET', 1, 99, 99, false, '00:01:00', true, '2026-03-09 16:05:58.170814-04', '2026-03-09 16:06:31.678451-04', 'Pediatria', '🩺', true, '05:00:00');
INSERT INTO clinicqueue.queue_settings VALUES ('E', 'CONTINUOUS', 1, 99, NULL, true, '00:01:00', true, '2026-02-27 00:13:34.321606-04', '2026-03-09 16:56:48.416863-04', 'Emergencia', '🚑', false, '05:00:00');


--
-- TOC entry 4532 (class 0 OID 55683)
-- Dependencies: 581
-- Data for Name: refresh_tokens; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.refresh_tokens VALUES (1, 1, 'ee22b8f844b399c8e24c6a1680ab977b3dbf04fa33c2bf329f125b4b1db3b51a74ca32eb58ddfd8a8a8d1dea9a285ff6b8af1504e0831a14facda5bf1b1428c0', '2026-03-13 09:39:52.796-04', false, NULL, '2026-03-06 09:39:52.799329-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (2, 1, 'ddd5f8b7ae29eecc9b3131545f21f272c102fd8ef18bd6040fc0ac2434555d0cb91495d948facef77cf34f954028d7035697e2a75537a5ebc57394b6ad27e817', '2026-03-13 09:47:37.011-04', false, NULL, '2026-03-06 09:47:37.012894-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (3, 1, 'eddc1a5cea443787e6a801208cbe713f3c9eb655e91a99ae0c1fbb9645304a7a41c10f08b3834e599a1c63ebc455569f03ddfc4b52e8d1099ae8e0f33811e558', '2026-03-13 09:51:46.002-04', false, NULL, '2026-03-06 09:51:46.005452-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (4, 1, '074d27229b7c4b378b90b7d89393adb5c6eae81f18368ca08ab023331067ca4f463740905d6fb14cb9f9f0a6221e59335848cec7eaa27f1a2a21537d71ec5ebe', '2026-03-13 10:21:09.081-04', false, NULL, '2026-03-06 10:21:09.08227-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (5, 1, '75a80b97b740a14f84aceba7bc253511e9d7a98109ef9fc453252f504e2a35232c9c7814d9da8a6bfa3cbceddcdd5b77a1667a72199d6d724b59c2885364f425', '2026-03-13 10:22:54.185-04', false, NULL, '2026-03-06 10:22:54.185885-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (6, 1, '1b7696ae6b5a412a2ab904242503b95537f2b40cada1505f6a4ff9dbf9866c2bed2520f84a43f09942ade6581c4737dd0a801e891f0135b34ab285cd3322daab', '2026-03-13 10:23:16.721-04', false, NULL, '2026-03-06 10:23:16.72356-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (7, 1, '179c630a1c0a81b7820116084d33172ee02572bea15b824d594e4a71069b992f42a2911b6760fb3dc1a4f38db76bb74452890cf41f11e05d2bc426656f6a0162', '2026-03-13 10:23:35.944-04', false, NULL, '2026-03-06 10:23:35.945694-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (8, 1, '0ff94659ee56cdbc103a6fbd81a655cd7599bf91b8cfc42cadc9a90585f1f4b88e1a3eac6e3785684436327f9a263b7330861d7920bde73627dc32dcb9a990fc', '2026-03-13 10:24:15.278-04', false, NULL, '2026-03-06 10:24:15.28069-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (9, 1, '9077210b705aa2223f96a5435319c68dd2c1850b87f633b976c04268087e3c134a947e40e0bdb3ad70cf7d0ad96b0cb1e786737780ee204fdcee27c97fb6057c', '2026-03-13 10:25:04.091-04', false, NULL, '2026-03-06 10:25:04.092779-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (10, 1, 'a6a5f5a19733171666a0272b48add2076b6e265109fca6618678b66e35e5e028730945c6629d46d4122212ca569dc312282f0a0629d9cc242ff91e3d3ea2645f', '2026-03-13 10:27:29.529-04', false, NULL, '2026-03-06 10:27:29.531455-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (11, 1, '8ae27c32bb116df70aff4ed2f6879c3d840b40cbe2e97c6ff6e10d0d95b55bc3ac9658fd8b4e691a968204ff3ba73097ca1edd67fbfb37da55b0ade421130a70', '2026-03-13 10:28:13.422-04', false, NULL, '2026-03-06 10:28:13.423829-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (12, 1, '79e56bba6b7235e19755fd45eeb6e83c0346e640d9596ba3c0b0c7c3bbb64db9730aaf9215d8a070c51456c1ef6c7b9cd0cdb08b088b7de5149121b3d71d81b7', '2026-03-13 10:30:08.32-04', false, NULL, '2026-03-06 10:30:08.321439-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (13, 1, '5d1c1aa169187eedb6ad1d63f61a7b365027711b0d66715d122d656ec2dd85e3671d557a62ee92985e7840cb1c06932d16bb0eff5ed5cbcaf00d118ef494b95e', '2026-03-13 10:30:37.529-04', false, NULL, '2026-03-06 10:30:37.530683-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (14, 1, 'f5fabd65e96a6264af4841f0c8ccad10fa3863cc781745828ace26cbc9102347ade7b460fc3394121aea1d916c0a47882fd81aa2721f5f73d3d82fb57c24a99d', '2026-03-13 10:32:27.001-04', false, NULL, '2026-03-06 10:32:27.003185-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (15, 1, '23dd5fb24fd1e018bd0352cf0ba2fdc8c0afef7d3ddb10dbbb166cde30f963663d52507fb5f68e69b4cf76293301c626fb8178657da973739929ca5263623d54', '2026-03-13 10:35:12.312-04', false, NULL, '2026-03-06 10:35:12.312985-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (16, 1, 'bede9d65bc744361fa98a12f8c761d495dc7d6a07c18ed0386c3d60a69dc4e23444a02fc213e5dfac5c9c6b059a6e5cea77fe7966c80dc2b10a565a5e5059be7', '2026-03-13 10:35:49.189-04', false, NULL, '2026-03-06 10:35:49.190258-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (17, 1, 'b5483330c93298877f0fe5c10be2e671dfa73019105977771916e747f1c3cec6ef1b71aa6fe766ec4538d9a5a72fbd92913e24f76a949ff222dd7a9c0e5ecf38', '2026-03-13 10:36:18.663-04', false, NULL, '2026-03-06 10:36:18.664795-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (18, 1, '0a0d4f85b93f30a876335a7e1a10369d37b9487c32a26333d3301f8d34a92b6d9f62a1e761a23bf9fdb4c2ec7602e815277c32b81b15f9a48ca9963a60ab1a78', '2026-03-13 10:51:41.225-04', false, NULL, '2026-03-06 10:51:41.226109-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (19, 7, '3fdc406205a436c515ffe227edf4eeacc209b58839da2c53f1b8835782a261ea1cf5867574db7aca664b5b46008db202066f4031874d9afa12ef9663837f6ba1', '2026-03-13 10:57:23.07-04', false, NULL, '2026-03-06 10:57:23.071662-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (20, 7, 'c83119d6cee42dc5319346498b819b9447b58c9f03098211940547e77ff10c049c3775f20a82a554253aec66f1c8f9e0b628d4ee43c4477941d4cf11077d91da', '2026-03-13 11:06:19.523-04', false, NULL, '2026-03-06 11:06:19.524337-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (21, 1, '76eb388e0ca81b0a1a04bb20592da26732acd9bcf8d24901aa8aafd3e061eb89d240a2c1692378e0fcdde5d9bffa2586dce3c1a7db3c90a62767e54334940fd6', '2026-03-13 11:06:37.205-04', false, NULL, '2026-03-06 11:06:37.205842-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (22, 7, 'f8b99ed2028b0f310d0c4be7c062bfecb95d0a0bb4ec6852a21c4edb68c849fa5c41375e8626d9aebb2c4a25bf1e4f58643c04909c6c3bd75be7b12b5e7086f6', '2026-03-13 11:10:19.864-04', false, NULL, '2026-03-06 11:10:19.865923-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (23, 1, 'd2c4fb91e8f1c89b01061a83de0ee54b7e28dc6948509f931b198edb63248b34bb277fe33f492f1ccfa088d20386e94fea471a7345baeaf6213eb04453f7aa1c', '2026-03-13 11:12:09.405-04', false, NULL, '2026-03-06 11:12:09.40706-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (24, 7, '2d079fc14dea063ab3200a754a4775ee144d9986da81c2204450c7163729955fcf952fa1bf054f14be2f93a879fa5666095c40ee24f528521ab4e521876fee24', '2026-03-13 11:21:13.259-04', false, NULL, '2026-03-06 11:21:13.260379-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (25, 1, '807a90fd7ffda65d9a1bdb98d30e95573141aaff9e06b128db06b85bcdc9e5b278a427c0d99e8171278f0f3748df3d56586d44f034db6c44ea73123643e0c605', '2026-03-13 11:22:06.987-04', false, NULL, '2026-03-06 11:22:06.988488-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (26, 7, '97de7dbd38f3c8690ddfd2b0371f6d09bf0ce86418e7a1ecaec27fe139f4642ee4ec33ae693b0d6c46ba3e3954ff1a121fe0d495dcb9023479264908cfaaefc5', '2026-03-13 11:23:33.174-04', false, NULL, '2026-03-06 11:23:33.176264-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (27, 1, 'c0f63a838d45f127586f1d6e7446d94d1c4cb61e75b81d6a44cd9b2a3f3456269811d6c4498c7f282736e7ba6e77ac3bd85f69c1e6331056b08daa562a92d9e0', '2026-03-13 11:23:52.954-04', false, NULL, '2026-03-06 11:23:52.956613-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (28, 1, '6917bbe632c800001fbc8e2420923682b0aa0dacc412ca9b464c1faed7770972b4747ae4aab15c44e432d0393904222511755f766cd4abcfbb4a487596e6bec1', '2026-03-13 11:28:30.664-04', false, NULL, '2026-03-06 11:28:30.664629-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (29, 1, '26483043a6579ce3eb965ceb3265d34b61276b535c33bfc6a016eefaae59a74e6e59611a6706bfdeec927cd0783a1f0fe8d5b42471db23c1b4c382df49da7f5b', '2026-03-13 11:57:22.843-04', false, NULL, '2026-03-06 11:57:22.845052-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (30, 7, '5ae60ed0fdd7eaf81b45ff8fcbfde907c6dfd4fd5db79ec99b6588fd87a78c9a9095321b993571d1b4d421d7b023a1f9eb180120356107152a08ae0fcbaa9ac7', '2026-03-13 12:04:32.825-04', false, NULL, '2026-03-06 12:04:32.828343-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (31, 1, 'e0a519af5528c9bbcb82d665c775fd465ebea65a65a60b595ede2d144a59ed75b2d7697b95403628ea4b95dde2bdf92a0c637dceec5146c1b1f73dfb1fc80eec', '2026-03-13 12:05:57.149-04', false, NULL, '2026-03-06 12:05:57.151066-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (32, 7, 'd213a148f8eed1f578eafdf242cc79487938c048a926cd6d2f7ecb1efb00859f224ba356a2115e520b06d19dfae415c98412e3bdf24500faf192144a25ebfa78', '2026-03-13 12:18:47.608-04', false, NULL, '2026-03-06 12:18:47.620196-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (33, 1, 'bbb55c553757b6a8467c0989255eff2b3c3334e6a0961814be71ee046af90da1b19cfae3aea59112b327158e0b2f3514e8b263fdbf696fc2b2265ffd3c8752a9', '2026-03-13 14:27:03.035-04', false, NULL, '2026-03-06 14:27:03.037692-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (34, 1, '1c93172129b5c4b3c74655e363f379521795dfa034c30fa8ff124f20239d032dc6e156c27c62f8974df44634d166f67e9d05cbf4cb7d57151a2e82799ff2737e', '2026-03-13 14:28:27.483-04', false, NULL, '2026-03-06 14:28:27.483998-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (35, 5, '5ad1b82c83ac3f77f23b0f6cc5bbf7777c4bd8130b67573fcdbe9553d1bcb703b441a2df03af1d8a820931e4a0efe550740116cca61da457452b0fb947cf70d4', '2026-03-13 14:30:47.004-04', false, NULL, '2026-03-06 14:30:47.005668-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (36, 1, '9040e82baf559c923e8727ce6445e817ae4270324c0da8b955447d1194ebf7d900959e1e4ce0ef8312a644b7bc8f8764b4ff430f1b0da0745c1a0554b555fb9c', '2026-03-13 14:31:54.538-04', false, NULL, '2026-03-06 14:31:54.539173-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (37, 7, '5cc21a67f99d8dc86a4f187af3dfb82a73fcaca1d78b304d87e1c3166d50c1c3f9aa2f0c614813f0426fb4022f3087de3b37146acc040cbc97541a36f632af0c', '2026-03-13 14:49:17.243-04', false, NULL, '2026-03-06 14:49:17.244744-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (38, 5, '36e93acf2d9ed53fd39b3b3e422f3f0ffc5f20a8fbe19614acf6777ce7d2617981801b5bb44750121c963ff1070c74b84ce55531dd79cf5a6aef17f5f0cc3f4d', '2026-03-13 14:49:51.312-04', false, NULL, '2026-03-06 14:49:51.313066-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (39, 1, 'b50d6917d3d5e601cf5908db518ba117d254a1b09d6eb5f365e3acece46f7c14b4627b24a5e6279551c02d26aba00b2ed9e6970211b2403ecb67ed77dc11ab7d', '2026-03-13 14:50:01.096-04', false, NULL, '2026-03-06 14:50:01.097229-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (40, 5, '0c706fe3f96b25f8e39ada12760707498266b90ba85cf4fd7f2b7eed312e37515328a7023e426035e18b0b466defe1eeda682cd3907d830663b7d479dfb521c3', '2026-03-13 14:52:15.388-04', false, NULL, '2026-03-06 14:52:15.394067-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (41, 5, '68442a13fcf59006c41a844877faa8ead8dddac1207b29146a26336d165f76e4644b449b45eb00bb7a191cc47c27340d5874f9a3ebafc9cb5f5fc6f4be9c6a96', '2026-03-13 14:53:06.206-04', false, NULL, '2026-03-06 14:53:06.207465-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (42, 3, '3b52e838dc835af2f5386e3cf4ba5d31251e5eec82d4928e24eafb0393010a1732c17f8dfe02e884415f9c98bd3b81d22e5f7c7a316118d1907d5e253bee527b', '2026-03-13 14:54:34.831-04', false, NULL, '2026-03-06 14:54:34.832045-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (43, 5, '677b2c44688b08aa8d37b14cadca4d6022fd93085ef2a3dabdb6e554f157a4a4b8a0645a15f4599dfdd035d6b95fba59eb8ba020990bf4a2f643d90d3cecad3e', '2026-03-13 15:11:08.859-04', false, NULL, '2026-03-06 15:11:08.861495-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (44, 5, 'd182965de6eb519401ce192ddeadb6811a801e43873719093e45d8544d665f80ff8a39888f812872f7ab5d953909b5e39236a6fd9560653557e611fcaf3be78f', '2026-03-13 15:21:18.948-04', false, NULL, '2026-03-06 15:21:18.949547-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (45, 5, 'f6953cbc267801237b55760ef0ce7be6d8db709196b4c93b0476e3e8f17e4cfe15141afa294c7b44f59fd248994a7016887a47a7150961307899d209dd36f078', '2026-03-13 15:23:37.471-04', false, NULL, '2026-03-06 15:23:37.472412-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (46, 3, 'c293b2e554d99af8f4a76dfdd92e3c42ad1fc2224022f089a6d6df47f64230a531f1b73bf92b9aded9169f7c6d9befc34885d4ad129f7e796225cc16ad082289', '2026-03-13 15:25:03.128-04', false, NULL, '2026-03-06 15:25:03.12873-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (47, 1, '5473e2112684cab8369c81f85814c2c268f4bc09520c04b2c17d1edb8e2e13dd5ef6240add6bb0aaae1635a3893e7a0cc8b842d1182718c45f451d025116b4a4', '2026-03-13 15:25:58.968-04', false, NULL, '2026-03-06 15:25:58.97193-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (48, 3, '5b621ec7d0893cf45ec589fc467f5241fbf2591557f0af29888e86092bf5ae933c547bb2429650766450226fce9057b3c83b370ea79be40b68fcc943e178f778', '2026-03-13 15:26:52.545-04', false, NULL, '2026-03-06 15:26:52.546127-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (49, 5, '7b909c4f2188f97cb00a32414ce74e0a1c7cb90fe8e5d2f18afbe114588145771dc7c494b223e01e579fd92e7e726ec710032112a8be62eaed04cd829b1c2bd2', '2026-03-13 15:27:08.826-04', false, NULL, '2026-03-06 15:27:08.827213-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (50, 3, 'e61aaa463dc0c0e76f40924617fe6a34366cfd97efda5845ecb1270cb14e763bb4f4f2e81e7c68772812fbb4721d00628c77a8e05ca45ace68a3960b16358b03', '2026-03-13 15:32:56.293-04', false, NULL, '2026-03-06 15:32:56.295111-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (51, 5, '962bd2ce7c8fb1771a0ab4111d23878c07013bb138d9d26001f20a8b7afa8b8b95592640cb009786e79394e84aaa657f178c4cad70161a2b6f8f20c37239e8a1', '2026-03-13 15:33:15.587-04', false, NULL, '2026-03-06 15:33:15.588274-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (52, 2, '0d881a6d7d603c37da3cd92e171034df15f45df1761843fb8aced772184902b28df6f57c26ff58d4d3620518823a51e7690c211a529b935d6a22fc884dad5f38', '2026-03-13 15:33:50.096-04', false, NULL, '2026-03-06 15:33:50.097399-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (53, 1, 'a86a48634c30ad84b72c3c01da49934c3095debc68d49e984857b46cea1efd3c7a26bc6c954ced0c2be99cd884b50eef53bf89e21c2eacd481fa52eb8f96bd38', '2026-03-13 15:34:08.658-04', false, NULL, '2026-03-06 15:34:08.659246-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (54, 5, 'c76a724b43b132aeb446c9de4e10669c8e46431b2f0b6840725b641d13eaae50bb9e07a8a93781e2abc8f378d4bc1114407984ba450413033c332fd0e4a6fa98', '2026-03-13 15:34:58.133-04', false, NULL, '2026-03-06 15:34:58.134646-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (55, 5, 'bb39d88bbd8cf7921a635c9acb871a55526b103e2ce0a1c46e5ea02da00fa287eb0039656a060c241511f32e7db52469737d359dd9be034c89f4d10258808d74', '2026-03-13 15:38:12.168-04', false, NULL, '2026-03-06 15:38:12.169967-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (56, 5, 'b0d09d0ccc9fd5e981ae9ab6a8b762678af5b9429e87ff2a60def58110a43130d1167aca4f4c42abf5cb38dd558f2f73e432169c8b353a676935702dd6fb4c87', '2026-03-13 15:43:06.37-04', false, NULL, '2026-03-06 15:43:06.374992-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (57, 5, '85be68af7627e710fe6ea7be9952ed3154c7e73c6a9ed7e0b5a5d27f9cfd10e1ab71a3d8991c816d915ffbb84e31be636e0ac74497eb54030ce0674fe1f3e116', '2026-03-13 15:44:11.729-04', false, NULL, '2026-03-06 15:44:11.730788-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (58, 5, '10d0ee2de21c494339c181284072b76e0fc666326632c27cbdc4409e67b35318bcfed6bb570685ff8ae9551c3581be9fcf40c7cce08cdeac3515b11ba0e454c5', '2026-03-13 15:52:43.541-04', false, NULL, '2026-03-06 15:52:43.543893-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (59, 7, 'cf98241f4e5c2e091476dca373dfdbca7313a4207ac9041d689276c68bc6f047393b55dc7f6335d2fd0d75dec3d6c116caf30b319b124546ac2052e62837ec83', '2026-03-13 15:53:13.134-04', false, NULL, '2026-03-06 15:53:13.136603-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (60, 5, '908da445928092a5defc10694a590a7b94716fae8e2990b2561d34cfc1d4dd803115dbfb98a297c10b572304de6da5fcee22e5f28a32e8941ef3f116f5f497e7', '2026-03-13 15:53:59.745-04', false, NULL, '2026-03-06 15:53:59.749985-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (61, 5, 'dafc17a81ff3f6f3731b81a62571af26d76e9223a749f06ee876f715f5e58cae1ba5a3e1b46b1b20b56539d54c907dafffdbd803734cdd67a305e120749d97e6', '2026-03-16 10:11:30.693-04', false, NULL, '2026-03-09 10:11:30.694507-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (62, 5, '39426a604dddc7da43e091747972dae2b2148f2d39ad71b124f4a3447f92fdbc9edb5e8a2c14af1a9043d23705513cc4876a748d6249fa135e10da2d5b397277', '2026-03-16 10:15:53.682-04', false, NULL, '2026-03-09 10:15:53.683948-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (63, 5, 'd49f8e2d365c2444b46ef26ce281ac41283c16d2c2532089b48893517e602e7149640f331c6b70d40a7314d16e81cb1be138d2493bc4bc38957170f98bba3efb', '2026-03-16 10:16:26.521-04', false, NULL, '2026-03-09 10:16:26.522737-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (64, 5, '74e65d7cacb1a6e9f19706e6913276fdc3ed74d814650e2b44693504d7aeb8bb0ceb3953f5748eca7ef25d922919990518be0cc2efb113ae8d27d0a5134b6356', '2026-03-16 10:16:55.272-04', false, NULL, '2026-03-09 10:16:55.273346-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (65, 5, 'f766e6e8dc26728bbc24c0a03d62c8cce0a2d90a2e9063d10e2d8dd46a33b5973f0ce64c69c524b4e42d98560562eb6b1cc0774812c2517bd523e9e99fbb916c', '2026-03-16 10:17:45.084-04', false, NULL, '2026-03-09 10:17:45.08539-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (66, 7, '9c8c27ffa47823dc6b5721288a1edec370188a6ed359e9f794cbf3e7450752ce366e35d8b37eaab0ff4adfc27fc45cfe19d6ef7a870213a7c533dcb1a88b27e3', '2026-03-16 10:18:12.119-04', false, NULL, '2026-03-09 10:18:12.120527-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (67, 5, '6c2ac8ff0ceb34c66a16742933b02af9784c6966b5ee17dec7cf0cbcecd6afad1b65b810088c25459bd937ad6c25136e339dceb857b963e0c6268af03fd34dcd', '2026-03-16 10:22:32.627-04', false, NULL, '2026-03-09 10:22:32.629421-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (68, 5, 'a5591a38ad8da171fe188e4802afd306ef7905ca7884d52a8a6c6d08b5234508bedaa7dea77e214a162fa5716bb34fbb7b1049ed581bf893f16d8823fea6213f', '2026-03-16 10:23:11.022-04', false, NULL, '2026-03-09 10:23:11.025048-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (69, 5, '45f2afec55aca669081a94c3b79baa473c40ed336f3a3f4ebaa2c3c9691540f9946259a588a34ee544df65224b653ea435ac24e9d4fdd84d3003ce00c6f63618', '2026-03-16 10:23:23.836-04', false, NULL, '2026-03-09 10:23:23.838667-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (70, 7, '500f5264b1e7954abf7dae2a9c835b91966bd3bd06cc0a661f7c3de31de1b835dd2e27111978a546e098d45ebee1741f26ddfd00819498a1a601cbc1d11debf5', '2026-03-16 10:25:36.227-04', false, NULL, '2026-03-09 10:25:36.227637-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (71, 5, '6c2fa442aa9a031b36b582c471e44e2a99dfb30a3186be09e242145dfb5c28b7560416d1d445f41045252dff472d47f1efabaa5f10fd95b4a776391f7dcdf185', '2026-03-16 10:31:45.594-04', false, NULL, '2026-03-09 10:31:45.595562-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (72, 2, '65fd89eab6ae4e26e026f756e1de7d0c4a3986da3ba59a05b77bf32215929eb4157a0374cbfcbd8d16c3b85a881e25b6cbe38961dccdb83fdce16788d3927d25', '2026-03-16 10:32:26.826-04', false, NULL, '2026-03-09 10:32:26.827362-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (73, 1, 'c37c8e893d05dd690bd404ca57583e32ed68ff7bac9304d306d3e40e68c4de97ce355b62218548cbe7050ea9191af5ccad79e4f8695011d6fbb3f17154eac9f7', '2026-03-16 10:32:40.842-04', false, NULL, '2026-03-09 10:32:40.843159-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (74, 3, 'd5f17a0389c5f98ac49d5f4a277fb7f3db2b17c29d3ce1eac45547616500de58780230a847455e6a55bcdc4aa4d23391540bea92ed5bb4a555ceef491ebb093f', '2026-03-16 10:33:11.676-04', false, NULL, '2026-03-09 10:33:11.67732-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (75, 5, 'a85562c8ddd514b4fcc2f426be530d9150989f107cbf1bf42d74c3bf5340863255fcd6fd53362facda61e003ff2ca74ca53e5724033bddc6ac5e0653b4ae12a7', '2026-03-16 10:33:27.096-04', false, NULL, '2026-03-09 10:33:27.097013-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (76, 1, '2972c01a8e384958ee3a5f1f80b6a01660c4600ec4f70717f2398deef897dd07731da38e3883d576d7152f10d9174a27711a7d769ace792c780fe7016467828a', '2026-03-16 10:36:09.475-04', false, NULL, '2026-03-09 10:36:09.476026-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (77, 1, '1453f2e8da7004da3ccce776b0100f294b5b2f8412a28a0c24e3f2c277ba450a9ec833e0019074ad30af845274b58a26437baea899f9495f1eeef8c0a848fc22', '2026-03-16 10:38:56.789-04', false, NULL, '2026-03-09 10:38:56.790042-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (78, 5, 'f4740028a9423512afc1da2962e0e71056014066262a89bfff703a46d3a3f10e38fae3d2bcec626fe0113cb5281cccc86283186f8400c61ee7b17548dab3eef1', '2026-03-16 10:49:01.874-04', false, NULL, '2026-03-09 10:49:01.874554-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (79, 7, 'a564f2af0b75a767870f63a0ecd88bf7f07ba9d4a33002b95d3e222e8c1f961dd4d133d7c10f44d25add0b74e4387d308fdea4db8333038a579486f5cd24e667', '2026-03-16 10:50:32.966-04', false, NULL, '2026-03-09 10:50:32.966993-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (80, 1, '35797b417e1824b5c16935102657b6606b1f2966e509d6b3e8b84be4384bc30b970cd728b29baa7fc59adf9adb40330d8bda167a5e0345e5feccc819c6606bbb', '2026-03-16 10:53:07.949-04', false, NULL, '2026-03-09 10:53:07.951081-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (81, 3, 'b85bd313d5cbb21c066cdcc7582a6ec834f1788f7fb473c5bfd67386bc7882f563ffc034f230f3327d7bd11b1b26b8148e3e103904b22b1e7a12c6ee43350edf', '2026-03-16 11:18:47.673-04', false, NULL, '2026-03-09 11:18:47.674273-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (82, 7, 'daceec57ba5eb092ef3508d5bb09482a5917b63e11bb23302712a7b1321e0a8d14f2aff4890d06d97f09d20c13d4f18f78516496d375ce6e34669e75a6afb69b', '2026-03-16 11:19:43.178-04', false, NULL, '2026-03-09 11:19:43.178608-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (83, 1, '20b62a488608d8c104631b7994d81a9394c9e131a476c6718b889680f39040103cf0dc189de7dad6b40e51ebaa8a3e7e6342a1ddedf33115bd196a886092187e', '2026-03-16 11:37:21.94-04', false, NULL, '2026-03-09 11:37:21.941842-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (84, 1, 'e485e13ada67c20880727b4d71cc21f0651b9e32fa0c4be7acf8e95993e8085df1641f8b044ee1a981fdae7f17e7fbceccbb9a5c05f627a3fcd63953a053bb00', '2026-03-16 12:32:16.277-04', false, NULL, '2026-03-09 12:32:16.278657-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (85, 7, '3011449ecc139b4249db7f099b0602e78b6471020ec2894f69760fdd65942a19ead2804bd10fb704043402091ce1204ded1411507349422835044aa8c522c3d6', '2026-03-16 12:38:28.691-04', false, NULL, '2026-03-09 12:38:28.693604-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (86, 7, '7ace8f7955dfa899d44602ac9b62e8cde587d321b7c44569104681609f98b5a8159f78387c73d3e5b008fc161f380ef11c07ce158da20666972e47b705892b07', '2026-03-16 12:42:18.921-04', false, NULL, '2026-03-09 12:42:18.922849-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (87, 5, '05e954ac82f2b2818311fdbbf9ea08940f7d09197a029866565429283aa29ba8731457ef2f38623cd30ec35bd2da0d070ecf3efeeaf509df05d430d9319f9d64', '2026-03-16 12:43:35.64-04', false, NULL, '2026-03-09 12:43:35.643946-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (88, 3, '58e8fe7d89a24bb584d5898fb8e765e374e09a0b1911fa89d724b97a271228078a7d9a53789240bd40951f8712b99727f78b97c70911238652405da7c3a81fe4', '2026-03-16 12:44:16.901-04', false, NULL, '2026-03-09 12:44:16.904908-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (89, 5, '8edffafa14012f4ee07953b950dc41fcd569171a1605b384b3ebe46ed1c6cd87fa636a4073b4946e23f63790ce87f3b5673bcc486434506f69d16362317a1f4b', '2026-03-16 14:35:37.793-04', false, NULL, '2026-03-09 14:35:37.795535-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (90, 1, '74b4995ec6f8f4ad15b3edb4f9fde93f46481fa262ca67e1bb10f61613452bad73a550fe926991c519ea46856ba4ba51c72b6784a76a4f89ba4852be463dbac0', '2026-03-16 14:41:00.949-04', false, NULL, '2026-03-09 14:41:00.951472-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (91, 3, 'a68a4347f5c11e8705c1a4c0cc0dd1531887f3952a38368751b3295a0aa6306b95bda177dc32fd5c0a38ea45b0cb9a4e9489ff5e33eec85809366271154dfa1e', '2026-03-16 15:10:10.094-04', false, NULL, '2026-03-09 15:10:10.095463-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (92, 7, '7d7072c30a62d122f9f694e0ab6db4132a3a6d83ee16fdbe48e641aee132bae08e0d6f9218e34afd8d125e7497d27e51670f647803bde87b477f5b7cc016faf4', '2026-03-16 15:11:06.551-04', false, NULL, '2026-03-09 15:11:06.553218-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (93, 1, 'd84af86d760013cd9d89ba642566dec22c8ef304aceec4f29c1010d1396f4a3a97c1bfda1acd7bd038325d972017d0d10f54d3e0e1835542ef982e3f4a5a023a', '2026-03-16 15:11:41.962-04', false, NULL, '2026-03-09 15:11:41.964174-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (94, 1, '25499f55e6df93717a46a6049fc7473a9338a081b3217243af8a28cf6115ff73bf5af46c754f816340b83ce99330193157cbb1ad0ccc6f9a20aa56fe642ba364', '2026-03-16 15:26:20.295-04', false, NULL, '2026-03-09 15:26:20.29742-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (95, 10, '4a4d1b7101514fa93e8fd32f17df7e2be12bfc83abb13d824dd5b0ca50f0ea71eb17f57367e3d0e80ada12c196cb3f37f63846604ae1785f6a0807042d11b2ca', '2026-03-16 15:36:13.934-04', false, NULL, '2026-03-09 15:36:13.935131-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (96, 1, '9dafdd0781ab37da3e3ec3312aa8c9ce6b01bac8501628c11a1f5e13b6617350486bafbc3244dc1c066be3a4d029437b891cd01c8835044923ff83c2ab2f1fa5', '2026-03-16 15:41:31.562-04', false, NULL, '2026-03-09 15:41:31.564841-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (97, 1, 'cbc0023ba67005bcf1dbc1c58b7ff04ea63d518e64e67a60b1e06a01a7c9607d182493578fa785e4656b34acddf2dbb14c592c208cc146d2eb18a2c5705b423b', '2026-03-16 16:06:06.556-04', false, NULL, '2026-03-09 16:06:06.557714-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (98, 1, '2d194a40cd0d802f07692c9a133cd26e80667c36850eab05e4efa8ad916c6264ddf3888ca2a72f1d1a791349f65e7ef7fc246ecd5efd29c589951b7d1082afdd', '2026-03-16 16:33:28.804-04', false, NULL, '2026-03-09 16:33:28.806655-04');
INSERT INTO clinicqueue.refresh_tokens VALUES (99, 1, '28757a8ea00a16722d9d872192fa5b140cbe829c1b6acc0607a7c9680ab38aa37e2fda46099f5f5b3047bee9cbcc8c7c21da1b561130cc8bdf8ce17faad30717', '2026-03-16 16:42:45.891-04', false, NULL, '2026-03-09 16:42:45.893145-04');


--
-- TOC entry 4519 (class 0 OID 55305)
-- Dependencies: 563
-- Data for Name: roles; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.roles VALUES (1, 'ADMIN', 'Administrador', 'Configura el sistema, catálogos y reportes', true, '2026-02-28 10:56:09.883408-04', '2026-02-28 10:56:09.883408-04');
INSERT INTO clinicqueue.roles VALUES (2, 'DESK', 'Front Desk', 'Crea turnos desde recepción', true, '2026-02-28 10:56:09.883408-04', '2026-02-28 10:56:09.883408-04');
INSERT INTO clinicqueue.roles VALUES (5, 'SUPERVISOR', 'Supervisor', 'Puede reasignar estaciones', true, '2026-02-28 18:21:33.588876-04', '2026-02-28 18:21:33.588876-04');
INSERT INTO clinicqueue.roles VALUES (4, 'KIOSK', 'Kiosk Station', 'Usuario autenticado para estación de autogestión', true, '2026-03-09 11:20:35.196731-04', '2026-03-09 11:52:21.195383-04');
INSERT INTO clinicqueue.roles VALUES (3, 'STATION', 'Estación', 'Opera una estación Doctor/Analista que atiende turnos (trazabilidad)', true, '2026-02-28 10:56:09.883408-04', '2026-03-09 15:41:09.3944-04');


--
-- TOC entry 4521 (class 0 OID 55343)
-- Dependencies: 565
-- Data for Name: station_users; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.station_users VALUES (2, 3, true, NULL, NULL, '2026-02-28 11:24:14.836965-04', 1);
INSERT INTO clinicqueue.station_users VALUES (5, 4, true, NULL, NULL, '2026-02-28 11:24:20.910217-04', 1);
INSERT INTO clinicqueue.station_users VALUES (1, 5, true, NULL, NULL, '2026-02-28 12:56:52.993698-04', 1);
INSERT INTO clinicqueue.station_users VALUES (7, 11, true, NULL, NULL, '2026-03-09 15:46:34.189766-04', NULL);


--
-- TOC entry 4515 (class 0 OID 55259)
-- Dependencies: 559
-- Data for Name: stations; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.stations VALUES (1, 'CONS_C01', 'Consultorio 1', 'C', 1, true, '2026-02-28 10:37:30.868006-04', '2026-02-28 10:37:30.868006-04');
INSERT INTO clinicqueue.stations VALUES (2, 'CONS_C02', 'Consultorio 2', 'C', 2, true, '2026-02-28 10:37:30.868006-04', '2026-02-28 10:37:30.868006-04');
INSERT INTO clinicqueue.stations VALUES (3, 'PSICO_P01', 'Psicología 1', 'P', 3, true, '2026-02-28 10:37:30.868006-04', '2026-02-28 10:37:30.868006-04');
INSERT INTO clinicqueue.stations VALUES (4, 'ODON_O01', 'Odontología 1', 'O', 4, true, '2026-02-28 10:37:30.868006-04', '2026-02-28 10:37:30.868006-04');
INSERT INTO clinicqueue.stations VALUES (5, 'LAB_L01', 'Laboratorio 1', 'L', 5, true, '2026-02-28 10:37:30.868006-04', '2026-02-28 10:37:30.868006-04');
INSERT INTO clinicqueue.stations VALUES (6, 'LAB_L02', 'Laboratorio 2', 'L', 6, true, '2026-02-28 10:37:30.868006-04', '2026-02-28 10:37:30.868006-04');
INSERT INTO clinicqueue.stations VALUES (7, 'EMERGENCIA', 'Emergencias', 'E', 7, true, '2026-02-28 10:37:30.868006-04', '2026-02-28 10:38:25.897687-04');
INSERT INTO clinicqueue.stations VALUES (8, 'C_CONSULTORIO_3', 'Consultorio 3', 'C', NULL, true, '2026-03-06 09:48:04.43633-04', '2026-03-06 09:48:04.43633-04');


--
-- TOC entry 4525 (class 0 OID 55458)
-- Dependencies: 569
-- Data for Name: ticket_events; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.ticket_events VALUES (69, 63, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 10:16:37.607106-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (70, 66, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:18:16.17468-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (71, 67, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:18:19.540308-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (72, 68, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:18:21.997033-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (73, 66, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 10:23:15.03447-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (74, 67, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 10:24:01.81996-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (76, 68, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 10:24:51.411247-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (77, 69, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:25:40.655778-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (78, 70, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:25:43.915941-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (79, 71, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:25:46.250172-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (80, 72, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:25:49.070126-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (81, 73, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:25:51.299105-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (82, 69, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 10:25:58.487569-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (83, 69, 'TRANSFERRED', 'LLAMADO', 'EN_COLA', 1, NULL, 5, '2026-03-09 10:26:18.503592-04', '{"reason": "Necesita se atendido con urgencia"}');
INSERT INTO clinicqueue.ticket_events VALUES (84, 70, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 10:26:33.449668-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (85, 71, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 10:27:25.500349-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (86, 72, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 10:28:01.991932-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (87, 74, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:31:17.402774-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (88, 75, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:31:19.713358-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (89, 76, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:31:21.534352-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (90, 77, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:31:23.259747-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (91, 72, 'STARTED', 'LLAMADO', 'EN_ATENCION', 1, NULL, 5, '2026-03-09 10:31:53.996924-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (92, 72, 'FINISHED', 'EN_ATENCION', 'FINALIZADO', 1, NULL, 5, '2026-03-09 10:32:00.606062-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (93, 73, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 10:32:14.016337-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (94, 74, 'CALLED', 'EN_COLA', 'LLAMADO', 2, 2, 3, '2026-03-09 10:33:16.251418-04', '{"module_id": 2, "station_id": 2}');
INSERT INTO clinicqueue.ticket_events VALUES (95, 74, 'STARTED', 'LLAMADO', 'EN_ATENCION', 2, NULL, 3, '2026-03-09 10:33:19.57049-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (96, 73, 'RECALLED', 'LLAMADO', 'LLAMADO', 1, NULL, 5, '2026-03-09 10:33:51.680119-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (97, 73, 'STARTED', 'LLAMADO', 'EN_ATENCION', 1, NULL, 5, '2026-03-09 10:33:58.590015-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (98, 73, 'FINISHED', 'EN_ATENCION', 'FINALIZADO', 1, NULL, 5, '2026-03-09 10:34:01.379764-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (99, 75, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 10:49:06.741671-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (100, 75, 'RECALLED', 'LLAMADO', 'LLAMADO', 1, NULL, 5, '2026-03-09 10:49:15.920419-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (101, 75, 'STARTED', 'LLAMADO', 'EN_ATENCION', 1, NULL, 5, '2026-03-09 10:49:43.553154-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (102, 75, 'FINISHED', 'EN_ATENCION', 'FINALIZADO', 1, NULL, 5, '2026-03-09 10:49:49.004864-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (103, 76, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 10:49:53.782226-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (104, 78, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:50:36.775279-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (105, 79, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:50:45.728171-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (106, 80, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:50:53.946061-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (107, 81, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 10:50:57.481839-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (108, 76, 'STARTED', 'LLAMADO', 'EN_ATENCION', 1, NULL, 5, '2026-03-09 10:51:15.423247-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (109, 76, 'FINISHED', 'EN_ATENCION', 'FINALIZADO', 1, NULL, 5, '2026-03-09 10:51:30.961993-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (110, 77, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 10:51:34.057453-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (111, 77, 'STARTED', 'LLAMADO', 'EN_ATENCION', 1, NULL, 5, '2026-03-09 10:52:11.256475-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (112, 74, 'FINISHED', 'EN_ATENCION', 'FINALIZADO', 2, NULL, 3, '2026-03-09 11:18:53.575141-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (113, 78, 'CALLED', 'EN_COLA', 'LLAMADO', 2, 2, 3, '2026-03-09 11:19:08.964769-04', '{"module_id": 2, "station_id": 2}');
INSERT INTO clinicqueue.ticket_events VALUES (114, 82, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 1, '2026-03-09 11:37:33.811539-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (115, 83, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 12:42:22.511702-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (116, 84, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 12:42:37.782728-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (117, 77, 'FINISHED', 'EN_ATENCION', 'FINALIZADO', 1, NULL, 5, '2026-03-09 12:43:42.73472-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (118, 79, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 12:43:46.127119-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (119, 79, 'RECALLED', 'LLAMADO', 'LLAMADO', 1, NULL, 5, '2026-03-09 12:43:58.449411-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (120, 78, 'STARTED', 'LLAMADO', 'EN_ATENCION', 2, NULL, 3, '2026-03-09 12:44:34.78436-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (121, 78, 'FINISHED', 'EN_ATENCION', 'FINALIZADO', 2, NULL, 3, '2026-03-09 12:44:44.336925-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (122, 80, 'CALLED', 'EN_COLA', 'LLAMADO', 2, 2, 3, '2026-03-09 12:44:50.402509-04', '{"module_id": 2, "station_id": 2}');
INSERT INTO clinicqueue.ticket_events VALUES (123, 80, 'RECALLED', 'LLAMADO', 'LLAMADO', 2, NULL, 3, '2026-03-09 12:45:09.580601-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (63, 61, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-06 15:53:34.469488-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (65, 63, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-06 15:53:40.909191-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (68, 61, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-06 15:54:04.026065-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (124, 80, 'STARTED', 'LLAMADO', 'EN_ATENCION', 2, NULL, 3, '2026-03-09 12:48:03.452576-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (125, 79, 'STARTED', 'LLAMADO', 'EN_ATENCION', 1, NULL, 5, '2026-03-09 14:35:46.645011-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (126, 79, 'FINISHED', 'EN_ATENCION', 'FINALIZADO', 1, NULL, 5, '2026-03-09 14:35:50.30765-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (127, 81, 'CALLED', 'EN_COLA', 'LLAMADO', 1, 1, 5, '2026-03-09 14:35:53.462347-04', '{"module_id": 1, "station_id": 1}');
INSERT INTO clinicqueue.ticket_events VALUES (128, 81, 'CANCELLED', 'LLAMADO', 'CANCELADO', NULL, NULL, 5, '2026-03-09 14:38:24.462447-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (129, 80, 'FINISHED', 'EN_ATENCION', 'FINALIZADO', 2, NULL, 3, '2026-03-09 15:10:15.398507-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (130, 85, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 15:11:08.652226-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (131, 86, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 7, '2026-03-09 15:11:18.781866-04', NULL);
INSERT INTO clinicqueue.ticket_events VALUES (132, 87, 'CREATED', NULL, 'EN_COLA', NULL, NULL, 10, '2026-03-09 15:37:28.371095-04', NULL);


--
-- TOC entry 4527 (class 0 OID 55494)
-- Dependencies: 571
-- Data for Name: ticket_transfers; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.ticket_transfers VALUES (10, 69, 'C', NULL, 1, 'E', NULL, NULL, 5, '2026-03-09 10:26:18.503592-04', 'Necesita se atendido con urgencia', NULL);


--
-- TOC entry 4523 (class 0 OID 55386)
-- Dependencies: 567
-- Data for Name: tickets; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.tickets VALUES (61, 'C', 28, 'C28', 'CANCELADO', 1, 1, 7, 5, 5, NULL, '2026-03-06 15:53:34.469488-04', '2026-03-06 15:54:04.026065-04', '2026-03-09 10:15:58.844604-04', NULL, '2026-03-06', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (63, 'C', 29, 'C29', 'CANCELADO', 1, 1, 7, 5, NULL, NULL, '2026-03-06 15:53:40.909191-04', '2026-03-09 10:16:37.607106-04', NULL, NULL, '2026-03-06', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (66, 'C', 1, 'C01', 'FINALIZADO', 1, 1, 7, 5, 5, 5, '2026-03-09 10:18:16.17468-04', '2026-03-09 10:23:15.03447-04', '2026-03-09 10:23:36.162135-04', '2026-03-09 10:23:48.518217-04', '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (67, 'C', 2, 'C02', 'NO_SHOW', 1, 1, 7, 5, NULL, NULL, '2026-03-09 10:18:19.540308-04', '2026-03-09 10:24:01.81996-04', NULL, NULL, '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (68, 'C', 3, 'C03', 'CANCELADO', 1, 1, 7, 5, NULL, NULL, '2026-03-09 10:18:21.997033-04', '2026-03-09 10:24:51.411247-04', NULL, NULL, '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (69, 'E', 3, 'E03', 'EN_COLA', NULL, NULL, 7, 5, NULL, NULL, '2026-03-09 10:25:40.655778-04', '2026-03-09 10:25:58.487569-04', NULL, NULL, '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (70, 'C', 5, 'C05', 'FINALIZADO', 1, 1, 7, 5, 5, 5, '2026-03-09 10:25:43.915941-04', '2026-03-09 10:26:33.449668-04', '2026-03-09 10:26:42.444145-04', '2026-03-09 10:26:52.237676-04', '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (71, 'C', 6, 'C06', 'FINALIZADO', 1, 1, 7, 5, 5, 5, '2026-03-09 10:25:46.250172-04', '2026-03-09 10:27:25.500349-04', '2026-03-09 10:27:28.501498-04', '2026-03-09 10:27:53.375824-04', '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (72, 'C', 7, 'C07', 'FINALIZADO', 1, 1, 7, 5, 5, 5, '2026-03-09 10:25:49.070126-04', '2026-03-09 10:28:01.991932-04', '2026-03-09 10:31:53.982185-04', '2026-03-09 10:32:00.602202-04', '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (73, 'C', 8, 'C08', 'FINALIZADO', 1, 1, 7, 5, 5, 5, '2026-03-09 10:25:51.299105-04', '2026-03-09 10:32:14.016337-04', '2026-03-09 10:33:58.579534-04', '2026-03-09 10:34:01.368646-04', '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (75, 'C', 10, 'C10', 'FINALIZADO', 1, 1, 7, 5, 5, 5, '2026-03-09 10:31:19.713358-04', '2026-03-09 10:49:06.741671-04', '2026-03-09 10:49:43.551677-04', '2026-03-09 10:49:48.992919-04', '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (76, 'C', 11, 'C11', 'FINALIZADO', 1, 1, 7, 5, 5, 5, '2026-03-09 10:31:21.534352-04', '2026-03-09 10:49:53.782226-04', '2026-03-09 10:51:15.420694-04', '2026-03-09 10:51:30.951597-04', '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (74, 'C', 9, 'C09', 'FINALIZADO', 2, 2, 7, 3, 3, 3, '2026-03-09 10:31:17.402774-04', '2026-03-09 10:33:16.251418-04', '2026-03-09 10:33:19.559054-04', '2026-03-09 11:18:53.566671-04', '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (82, 'C', 17, 'C17', 'EN_COLA', NULL, NULL, 1, NULL, NULL, NULL, '2026-03-09 11:37:33.811539-04', NULL, NULL, NULL, '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (83, 'C', 18, 'C18', 'EN_COLA', NULL, NULL, 7, NULL, NULL, NULL, '2026-03-09 12:42:22.511702-04', NULL, NULL, NULL, '2026-03-09', NULL, 'KIOSK', 1);
INSERT INTO clinicqueue.tickets VALUES (84, 'C', 19, 'C19', 'EN_COLA', NULL, NULL, 7, NULL, NULL, NULL, '2026-03-09 12:42:37.782728-04', NULL, NULL, NULL, '2026-03-09', NULL, 'KIOSK', 1);
INSERT INTO clinicqueue.tickets VALUES (77, 'C', 12, 'C12', 'FINALIZADO', 1, 1, 7, 5, 5, 5, '2026-03-09 10:31:23.259747-04', '2026-03-09 10:51:34.057453-04', '2026-03-09 10:52:11.244886-04', '2026-03-09 12:43:42.731074-04', '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (78, 'C', 13, 'C13', 'FINALIZADO', 2, 2, 7, 3, 3, 3, '2026-03-09 10:50:36.775279-04', '2026-03-09 11:19:08.964769-04', '2026-03-09 12:44:34.770513-04', '2026-03-09 12:44:44.333183-04', '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (79, 'C', 14, 'C14', 'FINALIZADO', 1, 1, 7, 5, 5, 5, '2026-03-09 10:50:45.728171-04', '2026-03-09 12:43:46.127119-04', '2026-03-09 14:35:46.621143-04', '2026-03-09 14:35:50.305319-04', '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (81, 'C', 16, 'C16', 'CANCELADO', 1, 1, 7, 5, NULL, NULL, '2026-03-09 10:50:57.481839-04', '2026-03-09 14:35:53.462347-04', NULL, NULL, '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (80, 'C', 15, 'C15', 'FINALIZADO', 2, 2, 7, 3, 3, 3, '2026-03-09 10:50:53.946061-04', '2026-03-09 12:44:50.402509-04', '2026-03-09 12:48:03.449176-04', '2026-03-09 15:10:15.384088-04', '2026-03-09', NULL, 'DESK', NULL);
INSERT INTO clinicqueue.tickets VALUES (85, 'O', 1, 'O01', 'EN_COLA', NULL, NULL, 7, NULL, NULL, NULL, '2026-03-09 15:11:08.652226-04', NULL, NULL, NULL, '2026-03-09', NULL, 'KIOSK', 1);
INSERT INTO clinicqueue.tickets VALUES (86, 'L', 1, 'L01', 'EN_COLA', NULL, NULL, 7, NULL, NULL, NULL, '2026-03-09 15:11:18.781866-04', NULL, NULL, NULL, '2026-03-09', NULL, 'KIOSK', 1);
INSERT INTO clinicqueue.tickets VALUES (87, 'E', 4, 'E04', 'EN_COLA', NULL, NULL, 10, NULL, NULL, NULL, '2026-03-09 15:37:28.371095-04', NULL, NULL, NULL, '2026-03-09', NULL, 'KIOSK', 2);


--
-- TOC entry 4520 (class 0 OID 55320)
-- Dependencies: 564
-- Data for Name: user_roles; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.user_roles VALUES (2, 2, '2026-02-28 18:22:18.693503-04', 1);
INSERT INTO clinicqueue.user_roles VALUES (1, 1, '2026-02-28 10:56:17.169708-04', 1);
INSERT INTO clinicqueue.user_roles VALUES (3, 3, '2026-02-28 10:56:29.47914-04', 1);
INSERT INTO clinicqueue.user_roles VALUES (5, 3, '2026-03-09 11:12:36.10411-04', 1);
INSERT INTO clinicqueue.user_roles VALUES (7, 4, '2026-03-06 10:55:58.027813-04', 1);
INSERT INTO clinicqueue.user_roles VALUES (10, 4, '2026-03-09 15:28:06.625124-04', NULL);
INSERT INTO clinicqueue.user_roles VALUES (11, 3, '2026-03-09 15:40:44.132496-04', NULL);


--
-- TOC entry 4537 (class 0 OID 55823)
-- Dependencies: 587
-- Data for Name: user_statuses; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.user_statuses VALUES ('ACTIVE', 'Active', true, 1, true);
INSERT INTO clinicqueue.user_statuses VALUES ('INACTIVE', 'Inactive', false, 2, true);
INSERT INTO clinicqueue.user_statuses VALUES ('ARCHIVED', 'Archived', false, 3, true);


--
-- TOC entry 4517 (class 0 OID 55286)
-- Dependencies: 561
-- Data for Name: users; Type: TABLE DATA; Schema: clinicqueue; Owner: postgres
--

INSERT INTO clinicqueue.users VALUES (1, 'admin', 'Administrador', 'admin@clinic.local', NULL, true, '2026-02-28 10:40:52.944547-04', '2026-03-09 16:42:45.907671-04', '2026-03-09 16:42:45.907671-04', '$2b$10$dKkyfLNQmBD9tK2GAQjHues9TAkTqXiUuoL3CJ9pCcbv/116VhxuS', false, NULL, NULL, 'ACTIVE');
INSERT INTO clinicqueue.users VALUES (5, 'doc_c03', 'Dr(a). Consultorio 1', 'doc.c01@clinic.local', NULL, true, '2026-02-28 12:56:39.162782-04', '2026-03-09 14:48:23.398216-04', '2026-03-09 14:35:37.800038-04', '$2b$10$dKkyfLNQmBD9tK2GAQjHues9TAkTqXiUuoL3CJ9pCcbv/116VhxuS', false, NULL, NULL, 'ACTIVE');
INSERT INTO clinicqueue.users VALUES (4, 'lab1', 'Analista Lab 1', 'lab1@clinic.local', NULL, true, '2026-02-28 10:40:52.944547-04', '2026-03-09 14:48:23.398216-04', NULL, '$2b$10$dKkyfLNQmBD9tK2GAQjHues9TAkTqXiUuoL3CJ9pCcbv/116VhxuS', false, NULL, NULL, 'ACTIVE');
INSERT INTO clinicqueue.users VALUES (2, 'acontreras', 'Amanda Contreras', 'acontreras@clinic.local', NULL, true, '2026-02-28 10:40:52.944547-04', '2026-03-09 14:48:23.398216-04', '2026-03-09 10:32:26.832943-04', '$2b$10$dKkyfLNQmBD9tK2GAQjHues9TAkTqXiUuoL3CJ9pCcbv/116VhxuS', false, NULL, NULL, 'ACTIVE');
INSERT INTO clinicqueue.users VALUES (3, 'doc_c02', 'Dr(a). Consultorio 2', 'doc.c02@clinic.local', NULL, true, '2026-02-28 10:40:52.944547-04', '2026-03-09 15:10:10.101464-04', '2026-03-09 15:10:10.101464-04', '$2b$10$dKkyfLNQmBD9tK2GAQjHues9TAkTqXiUuoL3CJ9pCcbv/116VhxuS', false, NULL, NULL, 'ACTIVE');
INSERT INTO clinicqueue.users VALUES (7, 'kiosk_lobby', 'Kiosko Lobby', 'lobby@clinicqueue.local', NULL, true, '2026-03-06 10:55:58.023915-04', '2026-03-09 15:11:06.564429-04', '2026-03-09 15:11:06.564429-04', '$2b$12$v6THMEIBghnVcQgrWAwwO.H7JM4dWgDlyGB8PQ40Ddyb9JwrCHLqG', false, NULL, NULL, 'ACTIVE');
INSERT INTO clinicqueue.users VALUES (10, 'kiosk_er', 'Kiosko Emer', 'er@clinicqueue.local', NULL, true, '2026-03-09 15:28:06.612158-04', '2026-03-09 15:36:13.939901-04', '2026-03-09 15:36:13.939901-04', '$2b$12$qAO6rpVdx3wQ754l1Y5FgOkZdscA7eCpESxq9z1zqAEi5VR9nckja', false, NULL, NULL, 'ACTIVE');
INSERT INTO clinicqueue.users VALUES (6, 'desk2', 'Front Desk 2', 'desk2@clinic.local', '809-000-0000', false, '2026-02-28 18:17:06.847639-04', '2026-03-09 15:39:43.399571-04', NULL, '$2b$10$dKkyfLNQmBD9tK2GAQjHues9TAkTqXiUuoL3CJ9pCcbv/116VhxuS', false, NULL, NULL, 'ARCHIVED');
INSERT INTO clinicqueue.users VALUES (11, 'doc_er', 'Janet Doe ER', 'jdoer@cliniciqueue.local', NULL, true, '2026-03-09 15:40:44.120325-04', '2026-03-09 15:40:44.120325-04', NULL, '$2b$12$kRqoP2IyQDuAVrkci0qJLuCQI2MuAsFLacxQX5ZtiDg3GnTZ2w.nS', false, NULL, NULL, 'ACTIVE');


--
-- TOC entry 4557 (class 0 OID 0)
-- Dependencies: 590
-- Name: daily_close_runs_run_id_seq; Type: SEQUENCE SET; Schema: clinicqueue; Owner: postgres
--

SELECT pg_catalog.setval('clinicqueue.daily_close_runs_run_id_seq', 1, true);


--
-- TOC entry 4558 (class 0 OID 0)
-- Dependencies: 572
-- Name: display_boards_board_id_seq; Type: SEQUENCE SET; Schema: clinicqueue; Owner: postgres
--

SELECT pg_catalog.setval('clinicqueue.display_boards_board_id_seq', 4, true);


--
-- TOC entry 4559 (class 0 OID 0)
-- Dependencies: 584
-- Name: kiosk_queues_kiosk_queue_id_seq; Type: SEQUENCE SET; Schema: clinicqueue; Owner: postgres
--

SELECT pg_catalog.setval('clinicqueue.kiosk_queues_kiosk_queue_id_seq', 5, true);


--
-- TOC entry 4560 (class 0 OID 0)
-- Dependencies: 582
-- Name: kiosks_kiosk_id_seq; Type: SEQUENCE SET; Schema: clinicqueue; Owner: postgres
--

SELECT pg_catalog.setval('clinicqueue.kiosks_kiosk_id_seq', 2, true);


--
-- TOC entry 4561 (class 0 OID 0)
-- Dependencies: 556
-- Name: modules_module_id_seq; Type: SEQUENCE SET; Schema: clinicqueue; Owner: postgres
--

SELECT pg_catalog.setval('clinicqueue.modules_module_id_seq', 8, true);


--
-- TOC entry 4562 (class 0 OID 0)
-- Dependencies: 580
-- Name: refresh_tokens_token_id_seq; Type: SEQUENCE SET; Schema: clinicqueue; Owner: postgres
--

SELECT pg_catalog.setval('clinicqueue.refresh_tokens_token_id_seq', 99, true);


--
-- TOC entry 4563 (class 0 OID 0)
-- Dependencies: 562
-- Name: roles_role_id_seq; Type: SEQUENCE SET; Schema: clinicqueue; Owner: postgres
--

SELECT pg_catalog.setval('clinicqueue.roles_role_id_seq', 5, true);


--
-- TOC entry 4564 (class 0 OID 0)
-- Dependencies: 558
-- Name: stations_station_id_seq; Type: SEQUENCE SET; Schema: clinicqueue; Owner: postgres
--

SELECT pg_catalog.setval('clinicqueue.stations_station_id_seq', 8, true);


--
-- TOC entry 4565 (class 0 OID 0)
-- Dependencies: 568
-- Name: ticket_events_event_id_seq; Type: SEQUENCE SET; Schema: clinicqueue; Owner: postgres
--

SELECT pg_catalog.setval('clinicqueue.ticket_events_event_id_seq', 132, true);


--
-- TOC entry 4566 (class 0 OID 0)
-- Dependencies: 570
-- Name: ticket_transfers_transfer_id_seq; Type: SEQUENCE SET; Schema: clinicqueue; Owner: postgres
--

SELECT pg_catalog.setval('clinicqueue.ticket_transfers_transfer_id_seq', 10, true);


--
-- TOC entry 4567 (class 0 OID 0)
-- Dependencies: 566
-- Name: tickets_ticket_id_seq; Type: SEQUENCE SET; Schema: clinicqueue; Owner: postgres
--

SELECT pg_catalog.setval('clinicqueue.tickets_ticket_id_seq', 87, true);


--
-- TOC entry 4568 (class 0 OID 0)
-- Dependencies: 560
-- Name: users_user_id_seq; Type: SEQUENCE SET; Schema: clinicqueue; Owner: postgres
--

SELECT pg_catalog.setval('clinicqueue.users_user_id_seq', 11, true);


--
-- TOC entry 4275 (class 2606 OID 55579)
-- Name: board_stations board_stations_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.board_stations
    ADD CONSTRAINT board_stations_pkey PRIMARY KEY (board_id, station_id);


--
-- TOC entry 4295 (class 2606 OID 55866)
-- Name: daily_close_runs daily_close_runs_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.daily_close_runs
    ADD CONSTRAINT daily_close_runs_pkey PRIMARY KEY (run_id);


--
-- TOC entry 4270 (class 2606 OID 55566)
-- Name: display_boards display_boards_board_code_key; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.display_boards
    ADD CONSTRAINT display_boards_board_code_key UNIQUE (board_code);


--
-- TOC entry 4272 (class 2606 OID 55564)
-- Name: display_boards display_boards_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.display_boards
    ADD CONSTRAINT display_boards_pkey PRIMARY KEY (board_id);


--
-- TOC entry 4289 (class 2606 OID 55784)
-- Name: kiosk_queues kiosk_queues_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.kiosk_queues
    ADD CONSTRAINT kiosk_queues_pkey PRIMARY KEY (kiosk_queue_id);


--
-- TOC entry 4283 (class 2606 OID 55749)
-- Name: kiosks kiosks_kiosk_code_key; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.kiosks
    ADD CONSTRAINT kiosks_kiosk_code_key UNIQUE (kiosk_code);


--
-- TOC entry 4285 (class 2606 OID 55747)
-- Name: kiosks kiosks_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.kiosks
    ADD CONSTRAINT kiosks_pkey PRIMARY KEY (kiosk_id);


--
-- TOC entry 4287 (class 2606 OID 55751)
-- Name: kiosks kiosks_user_id_key; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.kiosks
    ADD CONSTRAINT kiosks_user_id_key UNIQUE (user_id);


--
-- TOC entry 4222 (class 2606 OID 55250)
-- Name: modules modules_module_code_key; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.modules
    ADD CONSTRAINT modules_module_code_key UNIQUE (module_code);


--
-- TOC entry 4224 (class 2606 OID 55248)
-- Name: modules modules_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.modules
    ADD CONSTRAINT modules_pkey PRIMARY KEY (module_id);


--
-- TOC entry 4220 (class 2606 OID 55227)
-- Name: queue_counters pk_queue_counters; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.queue_counters
    ADD CONSTRAINT pk_queue_counters PRIMARY KEY (prefix, counter_key);


--
-- TOC entry 4217 (class 2606 OID 55215)
-- Name: queue_settings queue_settings_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.queue_settings
    ADD CONSTRAINT queue_settings_pkey PRIMARY KEY (prefix);


--
-- TOC entry 4279 (class 2606 OID 55690)
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (token_id);


--
-- TOC entry 4281 (class 2606 OID 55692)
-- Name: refresh_tokens refresh_tokens_token_key; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.refresh_tokens
    ADD CONSTRAINT refresh_tokens_token_key UNIQUE (token);


--
-- TOC entry 4240 (class 2606 OID 55315)
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (role_id);


--
-- TOC entry 4242 (class 2606 OID 55317)
-- Name: roles roles_role_code_key; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.roles
    ADD CONSTRAINT roles_role_code_key UNIQUE (role_code);


--
-- TOC entry 4250 (class 2606 OID 55350)
-- Name: station_users station_users_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.station_users
    ADD CONSTRAINT station_users_pkey PRIMARY KEY (station_id, user_id);


--
-- TOC entry 4227 (class 2606 OID 55269)
-- Name: stations stations_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.stations
    ADD CONSTRAINT stations_pkey PRIMARY KEY (station_id);


--
-- TOC entry 4229 (class 2606 OID 55271)
-- Name: stations stations_station_code_key; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.stations
    ADD CONSTRAINT stations_station_code_key UNIQUE (station_code);


--
-- TOC entry 4262 (class 2606 OID 55466)
-- Name: ticket_events ticket_events_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_events
    ADD CONSTRAINT ticket_events_pkey PRIMARY KEY (event_id);


--
-- TOC entry 4268 (class 2606 OID 55502)
-- Name: ticket_transfers ticket_transfers_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_transfers
    ADD CONSTRAINT ticket_transfers_pkey PRIMARY KEY (transfer_id);


--
-- TOC entry 4255 (class 2606 OID 55397)
-- Name: tickets tickets_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.tickets
    ADD CONSTRAINT tickets_pkey PRIMARY KEY (ticket_id);


--
-- TOC entry 4291 (class 2606 OID 55786)
-- Name: kiosk_queues uq_kiosk_queues; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.kiosk_queues
    ADD CONSTRAINT uq_kiosk_queues UNIQUE (kiosk_id, prefix);


--
-- TOC entry 4246 (class 2606 OID 55325)
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id);


--
-- TOC entry 4293 (class 2606 OID 55830)
-- Name: user_statuses user_statuses_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.user_statuses
    ADD CONSTRAINT user_statuses_pkey PRIMARY KEY (status_code);


--
-- TOC entry 4234 (class 2606 OID 55300)
-- Name: users users_email_key; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- TOC entry 4236 (class 2606 OID 55296)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- TOC entry 4238 (class 2606 OID 55298)
-- Name: users users_username_key; Type: CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- TOC entry 4257 (class 1259 OID 55490)
-- Name: gin_ticket_events_details; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX gin_ticket_events_details ON clinicqueue.ticket_events USING gin (details);


--
-- TOC entry 4263 (class 1259 OID 55546)
-- Name: gin_ticket_transfers_details; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX gin_ticket_transfers_details ON clinicqueue.ticket_transfers USING gin (details);


--
-- TOC entry 4276 (class 1259 OID 55590)
-- Name: ix_board_stations_board_order; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_board_stations_board_order ON clinicqueue.board_stations USING btree (board_id, display_order, station_id);


--
-- TOC entry 4277 (class 1259 OID 55591)
-- Name: ix_board_stations_station; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_board_stations_station ON clinicqueue.board_stations USING btree (station_id);


--
-- TOC entry 4273 (class 1259 OID 55569)
-- Name: ix_display_boards_active; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_display_boards_active ON clinicqueue.display_boards USING btree (is_active, board_code);


--
-- TOC entry 4218 (class 1259 OID 55233)
-- Name: ix_queue_counters_prefix; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_queue_counters_prefix ON clinicqueue.queue_counters USING btree (prefix);


--
-- TOC entry 4247 (class 1259 OID 55367)
-- Name: ix_station_users_station; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_station_users_station ON clinicqueue.station_users USING btree (station_id);


--
-- TOC entry 4248 (class 1259 OID 55366)
-- Name: ix_station_users_user; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_station_users_user ON clinicqueue.station_users USING btree (user_id);


--
-- TOC entry 4225 (class 1259 OID 55282)
-- Name: ix_stations_prefix_module; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_stations_prefix_module ON clinicqueue.stations USING btree (prefix, module_id);


--
-- TOC entry 4258 (class 1259 OID 55489)
-- Name: ix_ticket_events_station_time; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_ticket_events_station_time ON clinicqueue.ticket_events USING btree (station_id, event_at DESC);


--
-- TOC entry 4259 (class 1259 OID 55487)
-- Name: ix_ticket_events_ticket; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_ticket_events_ticket ON clinicqueue.ticket_events USING btree (ticket_id, event_at DESC);


--
-- TOC entry 4260 (class 1259 OID 55488)
-- Name: ix_ticket_events_type_time; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_ticket_events_type_time ON clinicqueue.ticket_events USING btree (event_type, event_at DESC);


--
-- TOC entry 4264 (class 1259 OID 55545)
-- Name: ix_ticket_transfers_from_prefix_time; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_ticket_transfers_from_prefix_time ON clinicqueue.ticket_transfers USING btree (from_prefix, transferred_at DESC);


--
-- TOC entry 4265 (class 1259 OID 55543)
-- Name: ix_ticket_transfers_ticket_time; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_ticket_transfers_ticket_time ON clinicqueue.ticket_transfers USING btree (ticket_id, transferred_at DESC);


--
-- TOC entry 4266 (class 1259 OID 55544)
-- Name: ix_ticket_transfers_to_prefix_time; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_ticket_transfers_to_prefix_time ON clinicqueue.ticket_transfers USING btree (to_prefix, transferred_at DESC);


--
-- TOC entry 4251 (class 1259 OID 55435)
-- Name: ix_tickets_module_status; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_tickets_module_status ON clinicqueue.tickets USING btree (module_id, status, created_at);


--
-- TOC entry 4252 (class 1259 OID 55433)
-- Name: ix_tickets_queue; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_tickets_queue ON clinicqueue.tickets USING btree (prefix, status, created_at, ticket_id);


--
-- TOC entry 4253 (class 1259 OID 55434)
-- Name: ix_tickets_station_status; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_tickets_station_status ON clinicqueue.tickets USING btree (station_id, status, called_at);


--
-- TOC entry 4243 (class 1259 OID 55341)
-- Name: ix_user_roles_role; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_user_roles_role ON clinicqueue.user_roles USING btree (role_id);


--
-- TOC entry 4244 (class 1259 OID 55342)
-- Name: ix_user_roles_user; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_user_roles_user ON clinicqueue.user_roles USING btree (user_id);


--
-- TOC entry 4230 (class 1259 OID 55301)
-- Name: ix_users_display_name; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_users_display_name ON clinicqueue.users USING btree (display_name);


--
-- TOC entry 4231 (class 1259 OID 55822)
-- Name: ix_users_is_archived; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_users_is_archived ON clinicqueue.users USING btree (is_archived);


--
-- TOC entry 4232 (class 1259 OID 55836)
-- Name: ix_users_status_code; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE INDEX ix_users_status_code ON clinicqueue.users USING btree (status_code);


--
-- TOC entry 4256 (class 1259 OID 55592)
-- Name: ux_tickets_active_prefix_number; Type: INDEX; Schema: clinicqueue; Owner: postgres
--

CREATE UNIQUE INDEX ux_tickets_active_prefix_number ON clinicqueue.tickets USING btree (prefix, tck_number) WHERE (status = ANY (ARRAY['EN_COLA'::clinicqueue.ticket_status, 'LLAMADO'::clinicqueue.ticket_status, 'EN_ATENCION'::clinicqueue.ticket_status]));


--
-- TOC entry 4346 (class 2620 OID 55568)
-- Name: display_boards trg_display_boards_normalize; Type: TRIGGER; Schema: clinicqueue; Owner: postgres
--

CREATE TRIGGER trg_display_boards_normalize BEFORE INSERT OR UPDATE ON clinicqueue.display_boards FOR EACH ROW EXECUTE FUNCTION clinicqueue.trg_display_boards_normalize();


--
-- TOC entry 4338 (class 2620 OID 55257)
-- Name: modules trg_modules_normalize; Type: TRIGGER; Schema: clinicqueue; Owner: postgres
--

CREATE TRIGGER trg_modules_normalize BEFORE INSERT OR UPDATE ON clinicqueue.modules FOR EACH ROW EXECUTE FUNCTION clinicqueue.trg_modules_normalize();


--
-- TOC entry 4337 (class 2620 OID 55235)
-- Name: queue_counters trg_queue_counters_norm; Type: TRIGGER; Schema: clinicqueue; Owner: postgres
--

CREATE TRIGGER trg_queue_counters_norm BEFORE INSERT OR UPDATE ON clinicqueue.queue_counters FOR EACH ROW EXECUTE FUNCTION clinicqueue.trg_queue_counters_norm();


--
-- TOC entry 4336 (class 2620 OID 55217)
-- Name: queue_settings trg_queue_settings_norm; Type: TRIGGER; Schema: clinicqueue; Owner: postgres
--

CREATE TRIGGER trg_queue_settings_norm BEFORE INSERT OR UPDATE ON clinicqueue.queue_settings FOR EACH ROW EXECUTE FUNCTION clinicqueue.trg_queue_settings_norm();


--
-- TOC entry 4342 (class 2620 OID 55319)
-- Name: roles trg_roles_normalize; Type: TRIGGER; Schema: clinicqueue; Owner: postgres
--

CREATE TRIGGER trg_roles_normalize BEFORE INSERT OR UPDATE ON clinicqueue.roles FOR EACH ROW EXECUTE FUNCTION clinicqueue.trg_roles_normalize();


--
-- TOC entry 4339 (class 2620 OID 55284)
-- Name: stations trg_stations_normalize; Type: TRIGGER; Schema: clinicqueue; Owner: postgres
--

CREATE TRIGGER trg_stations_normalize BEFORE INSERT OR UPDATE ON clinicqueue.stations FOR EACH ROW EXECUTE FUNCTION clinicqueue.trg_stations_normalize();


--
-- TOC entry 4344 (class 2620 OID 55492)
-- Name: ticket_events trg_ticket_events_validate; Type: TRIGGER; Schema: clinicqueue; Owner: postgres
--

CREATE TRIGGER trg_ticket_events_validate BEFORE INSERT ON clinicqueue.ticket_events FOR EACH ROW EXECUTE FUNCTION clinicqueue.trg_ticket_events_validate();


--
-- TOC entry 4345 (class 2620 OID 55548)
-- Name: ticket_transfers trg_ticket_transfers_validate; Type: TRIGGER; Schema: clinicqueue; Owner: postgres
--

CREATE TRIGGER trg_ticket_transfers_validate BEFORE INSERT OR UPDATE ON clinicqueue.ticket_transfers FOR EACH ROW EXECUTE FUNCTION clinicqueue.trg_ticket_transfers_validate();


--
-- TOC entry 4343 (class 2620 OID 55437)
-- Name: tickets trg_tickets_normalize; Type: TRIGGER; Schema: clinicqueue; Owner: postgres
--

CREATE TRIGGER trg_tickets_normalize BEFORE INSERT OR UPDATE ON clinicqueue.tickets FOR EACH ROW EXECUTE FUNCTION clinicqueue.trg_tickets_normalize();


--
-- TOC entry 4340 (class 2620 OID 55303)
-- Name: users trg_users_normalize; Type: TRIGGER; Schema: clinicqueue; Owner: postgres
--

CREATE TRIGGER trg_users_normalize BEFORE INSERT OR UPDATE ON clinicqueue.users FOR EACH ROW EXECUTE FUNCTION clinicqueue.trg_users_normalize();


--
-- TOC entry 4341 (class 2620 OID 55839)
-- Name: users trg_users_sync_status; Type: TRIGGER; Schema: clinicqueue; Owner: postgres
--

CREATE TRIGGER trg_users_sync_status BEFORE INSERT OR UPDATE ON clinicqueue.users FOR EACH ROW EXECUTE FUNCTION clinicqueue.trg_users_sync_status();


--
-- TOC entry 4328 (class 2606 OID 55580)
-- Name: board_stations board_stations_board_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.board_stations
    ADD CONSTRAINT board_stations_board_id_fkey FOREIGN KEY (board_id) REFERENCES clinicqueue.display_boards(board_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4329 (class 2606 OID 55585)
-- Name: board_stations board_stations_station_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.board_stations
    ADD CONSTRAINT board_stations_station_id_fkey FOREIGN KEY (station_id) REFERENCES clinicqueue.stations(station_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4335 (class 2606 OID 55867)
-- Name: daily_close_runs daily_close_runs_executed_by_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.daily_close_runs
    ADD CONSTRAINT daily_close_runs_executed_by_fkey FOREIGN KEY (executed_by) REFERENCES clinicqueue.users(user_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4332 (class 2606 OID 55797)
-- Name: kiosk_queues fk_kiosk_queues_created_by; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.kiosk_queues
    ADD CONSTRAINT fk_kiosk_queues_created_by FOREIGN KEY (created_by) REFERENCES clinicqueue.users(user_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4333 (class 2606 OID 55787)
-- Name: kiosk_queues fk_kiosk_queues_kiosk; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.kiosk_queues
    ADD CONSTRAINT fk_kiosk_queues_kiosk FOREIGN KEY (kiosk_id) REFERENCES clinicqueue.kiosks(kiosk_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4334 (class 2606 OID 55792)
-- Name: kiosk_queues fk_kiosk_queues_prefix; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.kiosk_queues
    ADD CONSTRAINT fk_kiosk_queues_prefix FOREIGN KEY (prefix) REFERENCES clinicqueue.queue_settings(prefix) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4331 (class 2606 OID 55752)
-- Name: kiosks fk_kiosks_user; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.kiosks
    ADD CONSTRAINT fk_kiosks_user FOREIGN KEY (user_id) REFERENCES clinicqueue.users(user_id);


--
-- TOC entry 4296 (class 2606 OID 55228)
-- Name: queue_counters fk_queue_counters_prefix; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.queue_counters
    ADD CONSTRAINT fk_queue_counters_prefix FOREIGN KEY (prefix) REFERENCES clinicqueue.queue_settings(prefix) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4297 (class 2606 OID 55251)
-- Name: modules modules_prefix_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.modules
    ADD CONSTRAINT modules_prefix_fkey FOREIGN KEY (prefix) REFERENCES clinicqueue.queue_settings(prefix) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4330 (class 2606 OID 55693)
-- Name: refresh_tokens refresh_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.refresh_tokens
    ADD CONSTRAINT refresh_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES clinicqueue.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 4305 (class 2606 OID 55361)
-- Name: station_users station_users_assigned_by_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.station_users
    ADD CONSTRAINT station_users_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES clinicqueue.users(user_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4306 (class 2606 OID 55351)
-- Name: station_users station_users_station_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.station_users
    ADD CONSTRAINT station_users_station_id_fkey FOREIGN KEY (station_id) REFERENCES clinicqueue.stations(station_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4307 (class 2606 OID 55356)
-- Name: station_users station_users_user_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.station_users
    ADD CONSTRAINT station_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES clinicqueue.users(user_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4298 (class 2606 OID 55277)
-- Name: stations stations_module_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.stations
    ADD CONSTRAINT stations_module_id_fkey FOREIGN KEY (module_id) REFERENCES clinicqueue.modules(module_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4299 (class 2606 OID 55272)
-- Name: stations stations_prefix_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.stations
    ADD CONSTRAINT stations_prefix_fkey FOREIGN KEY (prefix) REFERENCES clinicqueue.queue_settings(prefix) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4316 (class 2606 OID 55477)
-- Name: ticket_events ticket_events_module_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_events
    ADD CONSTRAINT ticket_events_module_id_fkey FOREIGN KEY (module_id) REFERENCES clinicqueue.modules(module_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4317 (class 2606 OID 55472)
-- Name: ticket_events ticket_events_station_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_events
    ADD CONSTRAINT ticket_events_station_id_fkey FOREIGN KEY (station_id) REFERENCES clinicqueue.stations(station_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4318 (class 2606 OID 55467)
-- Name: ticket_events ticket_events_ticket_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_events
    ADD CONSTRAINT ticket_events_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES clinicqueue.tickets(ticket_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4319 (class 2606 OID 55482)
-- Name: ticket_events ticket_events_user_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_events
    ADD CONSTRAINT ticket_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES clinicqueue.users(user_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4320 (class 2606 OID 55513)
-- Name: ticket_transfers ticket_transfers_from_module_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_transfers
    ADD CONSTRAINT ticket_transfers_from_module_id_fkey FOREIGN KEY (from_module_id) REFERENCES clinicqueue.modules(module_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4321 (class 2606 OID 55508)
-- Name: ticket_transfers ticket_transfers_from_prefix_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_transfers
    ADD CONSTRAINT ticket_transfers_from_prefix_fkey FOREIGN KEY (from_prefix) REFERENCES clinicqueue.queue_settings(prefix) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4322 (class 2606 OID 55518)
-- Name: ticket_transfers ticket_transfers_from_station_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_transfers
    ADD CONSTRAINT ticket_transfers_from_station_id_fkey FOREIGN KEY (from_station_id) REFERENCES clinicqueue.stations(station_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4323 (class 2606 OID 55503)
-- Name: ticket_transfers ticket_transfers_ticket_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_transfers
    ADD CONSTRAINT ticket_transfers_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES clinicqueue.tickets(ticket_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4324 (class 2606 OID 55528)
-- Name: ticket_transfers ticket_transfers_to_module_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_transfers
    ADD CONSTRAINT ticket_transfers_to_module_id_fkey FOREIGN KEY (to_module_id) REFERENCES clinicqueue.modules(module_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4325 (class 2606 OID 55523)
-- Name: ticket_transfers ticket_transfers_to_prefix_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_transfers
    ADD CONSTRAINT ticket_transfers_to_prefix_fkey FOREIGN KEY (to_prefix) REFERENCES clinicqueue.queue_settings(prefix) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4326 (class 2606 OID 55533)
-- Name: ticket_transfers ticket_transfers_to_station_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_transfers
    ADD CONSTRAINT ticket_transfers_to_station_id_fkey FOREIGN KEY (to_station_id) REFERENCES clinicqueue.stations(station_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4327 (class 2606 OID 55538)
-- Name: ticket_transfers ticket_transfers_transferred_by_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.ticket_transfers
    ADD CONSTRAINT ticket_transfers_transferred_by_fkey FOREIGN KEY (transferred_by) REFERENCES clinicqueue.users(user_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4308 (class 2606 OID 55418)
-- Name: tickets tickets_called_by_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.tickets
    ADD CONSTRAINT tickets_called_by_fkey FOREIGN KEY (called_by) REFERENCES clinicqueue.users(user_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4309 (class 2606 OID 55413)
-- Name: tickets tickets_created_by_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.tickets
    ADD CONSTRAINT tickets_created_by_fkey FOREIGN KEY (created_by) REFERENCES clinicqueue.users(user_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4310 (class 2606 OID 55428)
-- Name: tickets tickets_ended_by_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.tickets
    ADD CONSTRAINT tickets_ended_by_fkey FOREIGN KEY (ended_by) REFERENCES clinicqueue.users(user_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4311 (class 2606 OID 55805)
-- Name: tickets tickets_issued_by_kiosk_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.tickets
    ADD CONSTRAINT tickets_issued_by_kiosk_fkey FOREIGN KEY (issued_by_kiosk_id) REFERENCES clinicqueue.kiosks(kiosk_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4312 (class 2606 OID 55403)
-- Name: tickets tickets_module_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.tickets
    ADD CONSTRAINT tickets_module_id_fkey FOREIGN KEY (module_id) REFERENCES clinicqueue.modules(module_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4313 (class 2606 OID 55398)
-- Name: tickets tickets_prefix_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.tickets
    ADD CONSTRAINT tickets_prefix_fkey FOREIGN KEY (prefix) REFERENCES clinicqueue.queue_settings(prefix) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4314 (class 2606 OID 55423)
-- Name: tickets tickets_started_by_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.tickets
    ADD CONSTRAINT tickets_started_by_fkey FOREIGN KEY (started_by) REFERENCES clinicqueue.users(user_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4315 (class 2606 OID 55408)
-- Name: tickets tickets_station_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.tickets
    ADD CONSTRAINT tickets_station_id_fkey FOREIGN KEY (station_id) REFERENCES clinicqueue.stations(station_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4302 (class 2606 OID 55336)
-- Name: user_roles user_roles_assigned_by_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.user_roles
    ADD CONSTRAINT user_roles_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES clinicqueue.users(user_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4303 (class 2606 OID 55331)
-- Name: user_roles user_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.user_roles
    ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES clinicqueue.roles(role_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 4304 (class 2606 OID 55326)
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES clinicqueue.users(user_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4300 (class 2606 OID 55816)
-- Name: users users_archived_by_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.users
    ADD CONSTRAINT users_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES clinicqueue.users(user_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 4301 (class 2606 OID 55831)
-- Name: users users_status_code_fkey; Type: FK CONSTRAINT; Schema: clinicqueue; Owner: postgres
--

ALTER TABLE ONLY clinicqueue.users
    ADD CONSTRAINT users_status_code_fkey FOREIGN KEY (status_code) REFERENCES clinicqueue.user_statuses(status_code) ON UPDATE CASCADE ON DELETE RESTRICT;


-- Completed on 2026-03-09 16:59:31

--
-- PostgreSQL database dump complete
--

