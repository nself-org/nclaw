# ADR-0008: Legacy Desktop Handling (Frozen Archive)

**Status:** Accepted 2026-05-11  
**Context:** v1.1.0 shipped Flutter desktop. v1.1.1 replaces it with Tauri 2.  
**Decision:** Archive v1.1.0 Flutter desktop in `legacy-flutter-desktop/` branch; remove entirely in v1.2.0.  

## Context

v1.1.0 built desktop and mobile from Flutter. v1.1.1 migrates desktop to Tauri 2 for better native OS integration. Some users may want to reference the old codebase or continue running v1.1.0 for a period.

## Decision

- **v1.1.1:** Tauri 2 desktop ships as primary. v1.1.0 Flutter desktop is archived to `legacy-flutter-desktop/` branch with a `README.md` explaining the migration.
- **v1.2.0:** Legacy branch is deleted. Support ends.

No migration path is offered; v1.1.0 has no production users, so no users are stranded.

## Rationale

- **Archive, don't delete:** Allows reference and historical archaeology without cluttering the primary codebase.
- **Clear migration path:** README guides anyone still on v1.1.0 to upgrade to v1.1.1 (or later) and Tauri 2.
- **Time-bound:** Removing in v1.2.0 prevents indefinite technical debt.

## Consequences

**Positive:**
- Historical code is preserved for reference.
- No users are surprised by removal; archive is announced in release notes.

**Negative:**
- Archive takes up disk space (small).
- Maintenance burden if bug reports reference old code path.

## Alternatives Considered

- **Delete immediately:** Simpler codebase, but breaks users who want to stay on v1.1.0.
- **Keep legacy indefinitely:** Technical debt; old code path is never updated.

## References

- Git branching strategies: https://git-scm.com/book/en/v2/Git-Branching-Branching-Workflows
