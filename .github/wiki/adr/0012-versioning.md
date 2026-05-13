# ADR-0012: Versioning Policy (Monorepo Lockstep)

**Status:** Accepted 2026-05-11  
**Context:** Monorepo contains desktop, mobile, core, and protocol that must stay in sync.  
**Decision:** Single version number for entire monorepo. All components ship at v1.1.1.  

## Context

Before monorepo, versions drifted: desktop was v1.0.5, mobile was v1.1.0, core was v2.3. Users and developers confused about what's compatible.

## Decision

**nclaw monorepo uses one version: `v1.1.1`.** This applies to:
- Desktop application (Tauri)
- Mobile application (Flutter)
- Core library (Rust)
- Protocol schema
- Legacy archive (labeled as v1.1.0, archived)

All ship together on the same release date. `git tag v1.1.1` tags the entire monorepo.

Independent versioning may be introduced later (v2.x) if a real need emerges. Until then, lockstep.

## Rationale

- **Clarity:** One number = one consistent release.
- **Dependency guarantees:** If desktop says v1.1.1, mobile is v1.1.1, no version mismatch bugs.
- **Release simplicity:** One version bump, one release notes file, one tag.

## Consequences

**Positive:**
- No version confusion or compatibility gaps.

**Negative:**
- A small bugfix in mobile forces desktop release too (even if desktop is unaffected).
- Cannot patch desktop if mobile testing isn't ready.

## Alternatives Considered

- **Independent versions:** desktop v1.2.0, mobile v1.1.9, core v2.0.1. Flexibility, but confusing.
- **Semantic versioning per component:** Clearer intent, but complex release process.

## References

- Semantic versioning: https://semver.org/  
- Monorepo versioning strategies: https://gomonorepo.org/#release-management
