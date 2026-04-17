# Active Tasks: claw/

_Repo-specific tasks. Cross-repo sprint tracked at ~/Sites/nself/.claude/tasks/active.md (PPI)._

**Repo:** ɳClaw — open-source AI personal assistant client (Flutter + Rust FFI via libnclaw)
**Version:** 1.1.0+11
**Status:** Active development

---

## Current Phase

E2 Fleet C (Documentation Rebuild) completed 2026-04-17. No active repo-local phase.

See ecosystem-level phase: `/Volumes/X9/Sites/nself/.claude/phases/current/status.md`

---

## In Progress

(none)

---

## Up Next

- Coordinate with cli release workflow for ongoing command/plugin updates (per E2 doc-sync rule)
- Scaffold remaining native platform dirs: apps/ios/, apps/android/, apps/macos/, apps/web/, apps/desktop/
- Complete libnclaw FFI (per .claude/docs/libnclaw-audit.md 2026-03-13)

---

## Blocked

(none)

---

## Recently Completed

- [2026-04-17] E2 Fleet C: PRI 78→270 lines, README builds section, 14 wiki pages (build guides, features, Architecture-Deep-Dive, Plugin-Requirements), memory bootstrapped, ARCHITECTURE+TESTING docs, backend README plugin alignment

---

## Notes

- claw/ is on F14 AI attribution allowlist — can mention Claude/Anthropic in user-facing copy per nClaw product DNA
- Pro plugin requirements (per F06 ɳClaw bundle): REQUIRED ai/claw/mux + OPTIONAL voice/browser/google/notify/cron/claw-budget/claw-news/claw-web
- libnclaw FFI is Rust (client apps only); ai/claw/mux services themselves are Go
