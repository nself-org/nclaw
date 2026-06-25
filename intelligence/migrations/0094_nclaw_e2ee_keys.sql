-- Migration 0094 — nclaw_e2ee_keys
-- Public key fingerprints registry for E2EE key management.
-- Idempotent: all DDL uses IF NOT EXISTS.
-- Canonical: P4-E9 libnclaw E2EE schema (T05).
--
-- Reference: .claude/docs/p4/nclaw-access-surfaces-spec.md §7.1

-- nclaw_e2ee_keys: registry of active X25519 public keys per user.
-- fingerprint: SHA-256(public_key_bytes) as lowercase hex (64 chars).
-- public_key: raw 32-byte X25519 public key.
-- active: false means key has been rotated out.
CREATE TABLE IF NOT EXISTS nclaw_e2ee_keys (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    source_account_id  TEXT        NOT NULL DEFAULT 'primary',
    user_id            UUID        NOT NULL REFERENCES np_users(id) ON DELETE CASCADE,
    fingerprint        TEXT        NOT NULL CHECK (length(fingerprint) = 64),
    public_key         BYTEA       NOT NULL CHECK (length(public_key) = 32),
    active             BOOLEAN     NOT NULL DEFAULT true,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    rotated_at         TIMESTAMPTZ,
    UNIQUE (fingerprint)
);

CREATE INDEX IF NOT EXISTS nclaw_e2ee_keys_user_id_idx
    ON nclaw_e2ee_keys (user_id, active);

-- RLS: users see only their own keys; service role bypasses.
ALTER TABLE nclaw_e2ee_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS nclaw_e2ee_keys_user_select
    ON nclaw_e2ee_keys FOR SELECT TO hasura_user
    USING (source_account_id = current_setting('app.source_account_id', true));

CREATE POLICY IF NOT EXISTS nclaw_e2ee_keys_user_insert
    ON nclaw_e2ee_keys FOR INSERT TO hasura_user
    WITH CHECK (source_account_id = current_setting('app.source_account_id', true));
