-- Migration: 0092_nclaw_rls_hardening.sql
-- Ticket: P2-E5-W4-S7-T07
-- Audit: RLS isolation hardening pass across all six nclaw_* tables.
--
-- Audit findings (2026-06-14):
--   0090 (user_memories, memory_facts, session_wal):
--     - RLS enabled on all 3 tables. PASS.
--     - All USING clauses: current_setting('app.source_account_id', true). PASS.
--     - Policy names follow nclaw_{table}_isolation canonical pattern. PASS.
--   0091 (org_knowledge, org_facts, agent_checkpoints):
--     - RLS enabled on org_knowledge + org_facts. PASS.
--     - All USING clauses: current_setting('app.source_account_id', true). PASS.
--     - nclaw_agent_checkpoints has NO RLS — correct (system table). PASS.
--     - Policy names use _source_isolation suffix instead of canonical _isolation. MINOR GAP.
--       Corrective: standardize to nclaw_{table}_isolation naming pattern.
--
-- Corrective actions:
--   1. Rename nclaw_org_knowledge policy: _source_isolation → _isolation
--   2. Rename nclaw_org_facts policy: _source_isolation → _isolation
--   No other security gaps found. USING clauses and GUC key are correct in all policies.

-- ============================================================
-- UP
-- ============================================================

-- ── nclaw_org_knowledge: rename policy to canonical _isolation pattern ──────
DROP POLICY IF EXISTS nclaw_org_knowledge_source_isolation ON nclaw_org_knowledge;
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'nclaw_org_knowledge'
      AND policyname = 'nclaw_org_knowledge_isolation'
  ) THEN
    CREATE POLICY nclaw_org_knowledge_isolation ON nclaw_org_knowledge
      USING (source_account_id = current_setting('app.source_account_id', true));
  END IF;
END $$;

-- ── nclaw_org_facts: rename policy to canonical _isolation pattern ───────────
DROP POLICY IF EXISTS nclaw_org_facts_source_isolation ON nclaw_org_facts;
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'nclaw_org_facts'
      AND policyname = 'nclaw_org_facts_isolation'
  ) THEN
    CREATE POLICY nclaw_org_facts_isolation ON nclaw_org_facts
      USING (source_account_id = current_setting('app.source_account_id', true));
  END IF;
END $$;

-- ── Verification summary ─────────────────────────────────────────────────────
-- After this migration, ALL six nclaw_* tables have the following state:
--
--   Table                    | RLS | Policy name                       | GUC key
--   -------------------------|-----|-----------------------------------|-------------------
--   nclaw_user_memories      | YES | nclaw_user_memories_isolation     | app.source_account_id (true)
--   nclaw_memory_facts       | YES | nclaw_memory_facts_isolation      | app.source_account_id (true)
--   nclaw_session_wal        | YES | nclaw_session_wal_isolation       | app.source_account_id (true)
--   nclaw_org_knowledge      | YES | nclaw_org_knowledge_isolation     | app.source_account_id (true)
--   nclaw_org_facts          | YES | nclaw_org_facts_isolation         | app.source_account_id (true)
--   nclaw_agent_checkpoints  | NO  | (none — system table)             | N/A

-- ============================================================
-- DOWN
-- ============================================================

-- /* DOWN
-- -- Restore original 0091 policy names (before this migration renamed them)
-- DROP POLICY IF EXISTS nclaw_org_knowledge_isolation ON nclaw_org_knowledge;
-- CREATE POLICY nclaw_org_knowledge_source_isolation ON nclaw_org_knowledge
--   USING (source_account_id = current_setting('app.source_account_id', true));
--
-- DROP POLICY IF EXISTS nclaw_org_facts_isolation ON nclaw_org_facts;
-- CREATE POLICY nclaw_org_facts_source_isolation ON nclaw_org_facts
--   USING (source_account_id = current_setting('app.source_account_id', true));
-- */
