-- Migration 0093 — nclaw_e2ee_sessions
-- Ephemeral per-conversation key registry for E2EE transport.
-- Idempotent: all DDL uses IF NOT EXISTS.
-- Canonical: P4-E9 libnclaw E2EE schema (T05).
--
-- Isolation: source_account_id TEXT (consumer multi-app pattern per Convention Wall).
-- RLS GUC key: current_setting('app.source_account_id', true)
--
-- Reference: .claude/docs/p4/nclaw-access-surfaces-spec.md §7.1

-- nclaw_e2ee_sessions: tracks ephemeral per-conversation E2EE session state.
-- ek_pub: ephemeral X25519 public key (32 bytes, binary).
-- is_active: soft-delete flag; inactive sessions are not decrypted.
-- expires_at: TTL for session key rotation.
CREATE TABLE IF NOT EXISTS nclaw_e2ee_sessions (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    source_account_id  TEXT        NOT NULL DEFAULT 'primary',
    user_id            UUID        NOT NULL REFERENCES np_users(id) ON DELETE CASCADE,
    session_key_id     TEXT        NOT NULL,
    ek_pub             BYTEA       NOT NULL CHECK (length(ek_pub) = 32),
    is_active          BOOLEAN     NOT NULL DEFAULT true,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at         TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '24 hours'),
    UNIQUE (user_id, session_key_id, source_account_id)
);

CREATE INDEX IF NOT EXISTS nclaw_e2ee_sessions_user_id_idx
    ON nclaw_e2ee_sessions (user_id);

CREATE INDEX IF NOT EXISTS nclaw_e2ee_sessions_active_expires_idx
    ON nclaw_e2ee_sessions (expires_at)
    WHERE is_active = true;

-- RLS: users see only their own sessions; service role bypasses.
ALTER TABLE nclaw_e2ee_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS nclaw_e2ee_sessions_user_select
    ON nclaw_e2ee_sessions FOR SELECT TO hasura_user
    USING (source_account_id = current_setting('app.source_account_id', true));

CREATE POLICY IF NOT EXISTS nclaw_e2ee_sessions_user_insert
    ON nclaw_e2ee_sessions FOR INSERT TO hasura_user
    WITH CHECK (source_account_id = current_setting('app.source_account_id', true));
