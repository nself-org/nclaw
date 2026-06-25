-- Migration 0095 — nclaw_intelligence_sessions
-- gRPC session state tracking for the intelligence service.
-- Idempotent: all DDL uses IF NOT EXISTS.
-- Canonical: P4-E9 intelligence gRPC schema (T05).
--
-- Reference: .claude/docs/p4/nclaw-access-surfaces-spec.md §7.1

-- nclaw_intelligence_sessions: tracks active gRPC intelligence service sessions.
-- e2ee_session_id: optional FK to nclaw_e2ee_sessions (NULL if no E2EE).
-- role_scope: 'personal' (default) or 'devops' (elevated scope for tool calls).
-- source_account_id: multi-app isolation key (per Convention Wall).
CREATE TABLE IF NOT EXISTS nclaw_intelligence_sessions (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    source_account_id  TEXT        NOT NULL DEFAULT 'primary',
    user_id            UUID        NOT NULL REFERENCES np_users(id) ON DELETE CASCADE,
    e2ee_session_id    UUID        REFERENCES nclaw_e2ee_sessions(id) ON DELETE SET NULL,
    role_scope         TEXT        NOT NULL DEFAULT 'personal'
                                   CHECK (role_scope IN ('personal', 'devops')),
    started_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_active_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at           TIMESTAMPTZ,
    retrieval_path     TEXT,
    request_count      INTEGER     NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS nclaw_intelligence_sessions_user_id_idx
    ON nclaw_intelligence_sessions (user_id, source_account_id);

CREATE INDEX IF NOT EXISTS nclaw_intelligence_sessions_active_idx
    ON nclaw_intelligence_sessions (last_active_at)
    WHERE ended_at IS NULL;

-- RLS: users see only their own sessions; service role bypasses.
ALTER TABLE nclaw_intelligence_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS nclaw_intelligence_sessions_user_select
    ON nclaw_intelligence_sessions FOR SELECT TO hasura_user
    USING (source_account_id = current_setting('app.source_account_id', true));

CREATE POLICY IF NOT EXISTS nclaw_intelligence_sessions_user_insert
    ON nclaw_intelligence_sessions FOR INSERT TO hasura_user
    WITH CHECK (source_account_id = current_setting('app.source_account_id', true));
