-- Migration: 001_refresh_tokens
-- Creates the refresh_tokens table in clinicqueue schema.
-- Run once before starting the API.
-- Safe to run multiple times (uses IF NOT EXISTS).

CREATE TABLE IF NOT EXISTS clinicqueue.refresh_tokens (
    token_id   BIGSERIAL PRIMARY KEY,
    user_id    INTEGER       NOT NULL REFERENCES clinicqueue.users(user_id) ON DELETE CASCADE,
    token      VARCHAR(256)  NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ   NOT NULL,
    revoked    BOOLEAN       NOT NULL DEFAULT false,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_token     ON clinicqueue.refresh_tokens(token);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id   ON clinicqueue.refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires_at ON clinicqueue.refresh_tokens(expires_at);

-- Optional: auto-purge expired/revoked tokens older than 30 days
-- (run manually or via a pg_cron job)
-- DELETE FROM clinicqueue.refresh_tokens
-- WHERE (revoked = true OR expires_at < now()) AND created_at < now() - INTERVAL '30 days';
