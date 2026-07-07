-- ──────────────────────────────────────────────────────────────────────────────
-- 05-visit-plans.sql
-- Multi-queue visit plans: pre-register a patient into an ordered chain of
-- queues at intake (e.g. Laboratorio -> Imágenes). Each step's ticket is
-- created lazily as the prior step finishes, so a future step never sits in
-- EN_COLA before its turn. All statements are idempotent.
-- ──────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS clinicqueue.visit_plans (
    visit_plan_id BIGSERIAL PRIMARY KEY,
    created_by    BIGINT NULL REFERENCES clinicqueue.users(user_id) ON DELETE SET NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS clinicqueue.visit_plan_steps (
    step_id       BIGSERIAL PRIMARY KEY,
    visit_plan_id BIGINT NOT NULL REFERENCES clinicqueue.visit_plans(visit_plan_id) ON DELETE CASCADE,
    step_order    INTEGER NOT NULL CHECK (step_order >= 1),
    prefix        TEXT NOT NULL REFERENCES clinicqueue.queue_settings(prefix) ON UPDATE CASCADE,
    ticket_id     BIGINT NULL REFERENCES clinicqueue.tickets(ticket_id) ON DELETE SET NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ux_visit_plan_steps_order  UNIQUE (visit_plan_id, step_order),
    CONSTRAINT ux_visit_plan_steps_prefix UNIQUE (visit_plan_id, prefix)
);

CREATE INDEX IF NOT EXISTS ix_visit_plan_steps_plan ON clinicqueue.visit_plan_steps (visit_plan_id, step_order);

ALTER TABLE clinicqueue.tickets
    ADD COLUMN IF NOT EXISTS visit_plan_id BIGINT NULL
        REFERENCES clinicqueue.visit_plans(visit_plan_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS ix_tickets_visit_plan ON clinicqueue.tickets (visit_plan_id) WHERE visit_plan_id IS NOT NULL;
