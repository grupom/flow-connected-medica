-- ──────────────────────────────────────────────────────────────────────────────
-- 04-ad-campaigns.sql
-- Display board ad rotation (video / image sequence) + priority interrupt config.
-- All statements are idempotent (IF NOT EXISTS / CREATE OR REPLACE).
-- ──────────────────────────────────────────────────────────────────────────────

-- ── 1. display_boards — ad campaign columns ───────────────────────────────────

ALTER TABLE clinicqueue.display_boards
    ADD COLUMN IF NOT EXISTS ad_media_type       VARCHAR(20)  NOT NULL DEFAULT 'none'
        CHECK (ad_media_type IN ('none', 'video', 'image_sequence')),
    ADD COLUMN IF NOT EXISTS ad_video_filename    VARCHAR(255) NULL,
    ADD COLUMN IF NOT EXISTS ad_images            JSONB        NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS ad_rotation_seconds  INTEGER      NOT NULL DEFAULT 20
        CHECK (ad_rotation_seconds BETWEEN 3 AND 600),
    ADD COLUMN IF NOT EXISTS ad_interrupt_cooldown_seconds INTEGER NOT NULL DEFAULT 8
        CHECK (ad_interrupt_cooldown_seconds BETWEEN 1 AND 120),
    ADD COLUMN IF NOT EXISTS ad_uploaded_at        TIMESTAMPTZ NULL,
    ADD COLUMN IF NOT EXISTS ad_uploaded_by        BIGINT      NULL
        REFERENCES clinicqueue.users(user_id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS ad_version            INTEGER     NOT NULL DEFAULT 0;

-- ── 2. get_board_snapshot — expose ad campaign config to the public board ────
-- Identical to the previous live definition, plus the ad_* fields nested under
-- the `board` object so the TV client can drive ad rotation from one poll.

CREATE OR REPLACE FUNCTION clinicqueue.get_board_snapshot(p_board_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_code text := upper(trim(p_board_code));

  v_board_id bigint;
  v_board_name text;
  v_location text;

  v_show_last_called boolean;
  v_show_last_in_service int;
  v_show_waiting_count boolean;
  v_sound_override boolean;

  v_ad_media_type text;
  v_ad_video_filename text;
  v_ad_images jsonb;
  v_ad_rotation_seconds int;
  v_ad_interrupt_cooldown_seconds int;
  v_ad_version int;

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
    b.sound_enabled_override,
    b.ad_media_type,
    b.ad_video_filename,
    b.ad_images,
    b.ad_rotation_seconds,
    b.ad_interrupt_cooldown_seconds,
    b.ad_version
  INTO
    v_board_id,
    v_board_name,
    v_location,
    v_show_last_called,
    v_show_last_in_service,
    v_show_waiting_count,
    v_sound_override,
    v_ad_media_type,
    v_ad_video_filename,
    v_ad_images,
    v_ad_rotation_seconds,
    v_ad_interrupt_cooldown_seconds,
    v_ad_version
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
      'sound_enabled_effective', v_sound_effective,
      'ad_media_type', v_ad_media_type,
      'ad_video_filename', v_ad_video_filename,
      'ad_images', v_ad_images,
      'ad_rotation_seconds', v_ad_rotation_seconds,
      'ad_interrupt_cooldown_seconds', v_ad_interrupt_cooldown_seconds,
      'ad_version', v_ad_version
    ),
    'generated_at', v_now,
    'now_calling', v_now_calling,
    'in_service', v_in_service,
    'waiting_counts', v_waiting
  );
END;
$function$;
