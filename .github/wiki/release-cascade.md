# Release Cascade Architecture (v1.1.1)

## Overview

The nSelf release cascade orchestrates simultaneous releases across 12 repositories, 5 package registries, 3 app stores, and 2 cloud platforms.

```
┌────────────────┐
│  Release Gate  │  S0-S22 exit criteria verification
└────────────────┘
         ↓
┌────────────────┐
│ Version Bump   │  Update package.json, Cargo.toml, pubspec.yaml (atomic)
└────────────────┘
         ↓
┌─────────────────────────────────────┐
│ Staging: Tag + Smoke Tests          │  Validate on staging before prod
└─────────────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│ Production: Tag + GitHub Releases   │  Point of no return
└─────────────────────────────────────┘
         ↓
┌────────────────┐
│  Announce      │  Changelog + social posts
└────────────────┘
         ↓
┌─────────────────────────────────────────────────────────────────┐
│                   Parallel Publishing (Step 7)                 │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐          │
│  │ npm      │ │ PyPI     │ │crates.io │ │ Homebrew │          │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                        │
│  │ App Store│ │Goog Play │ │ Docker   │                        │
│  └──────────┘ └──────────┘ └──────────┘                        │
└─────────────────────────────────────────────────────────────────┘
         ↓
┌────────────────────┐
│ Bundle Smoke Tests │  Verify all releases work together
└────────────────────┘
         ↓
┌────────────────────┐
│  48h Soak Monitor  │  Production stability check
└────────────────────┘
         ↓
┌────────────────────┐
│  Audit Log Sign    │  Immutability record
└────────────────────┘
```

## Scripts (22 total)

| Script | Purpose |
|--------|---------|
| `release-gate.sh` | Pre-release verification (S0-S22 exit criteria) |
| `version-bump-cascade.sh` | Atomic version update across all 12 repos |
| `prod-tag.sh` | Create git tags + GitHub Releases |
| `staging-smoke.sh` | Post-staging smoke tests |
| `announce.sh` | Generate changelog + announcement |
| `npm-publish.sh` | npm publish for admin + plugins + SDKs |
| `sdk-publish.sh` | Publish SDKs (TS, Python, Go, Flutter) |
| `crates-io-publish.sh` | Publish nclaw-core, nclaw-protocol to crates.io |
| `homebrew-sync.sh` | Update Homebrew tap formula |
| `docker-build-push.sh` | Build + push Docker images |
| `ping-api-redeploy.sh` | Redeploy ping_api license validation |
| `vercel-verify.sh` | Verify Vercel deployments (web subapps) |
| `wiki-sync.sh` | Sync wiki + SPORT to docs.nself.org |
| `tauri-updater-push.sh` | Push Tauri updater manifest |
| `desktop-installers.sh` | Trigger macOS/Windows/Linux builds |
| `mobile-publish.sh` | App Store + Google Play submission |
| `bundle-smoke.sh` | Post-release integration smoke tests |
| `soak-48h.sh` | Monitor production for 48 hours |
| `audit-log-sign.sh` | Sign release audit log |
| `release-cascade.sh` | Orchestrator (calls all steps in sequence) |
| `.github/workflows/release-cascade.yml` | GitHub Actions workflow |
| `release-runbook.md` | Operator instructions |

## Secrets Required

| Secret | Used by | Example |
|--------|---------|---------|
| `NPM_TOKEN` | npm-publish | `npm_...` |
| `CARGO_REGISTRY_TOKEN` | crates-io-publish | `cargo_...` |
| `DOCKER_USERNAME` | docker-build-push | Docker Hub user |
| `DOCKER_PASSWORD` | docker-build-push | Docker Hub token |
| `VERCEL_TOKEN` | vercel-verify + ping-api-redeploy | `vercel_...` |
| `GPG_SIGNING_KEY_ID` | audit-log-sign | GPG fingerprint |
| `GITHUB_TOKEN` | prod-tag (auto) | GitHub (auto-provided) |

## Idempotency

All scripts are idempotent:
- Re-running `release-gate.sh` produces consistent results
- `version-bump-cascade.sh` can be re-run; idempotent edit
- Tag creation fails gracefully if tag already exists
- Publish commands check for existing releases and skip

## Manual Invocation

```bash
# Full cascade (7 steps)
bash nclaw/scripts/release-cascade.sh 1.1.1 all

# Individual steps
bash nclaw/scripts/release-gate.sh
bash nclaw/scripts/release-cascade.sh 1.1.1 bump
bash nclaw/scripts/release-cascade.sh 1.1.1 staging
bash nclaw/scripts/release-cascade.sh 1.1.1 smoke
bash nclaw/scripts/release-cascade.sh 1.1.1 prod
bash nclaw/scripts/release-cascade.sh 1.1.1 announce
bash nclaw/scripts/release-cascade.sh 1.1.1 publish
```

## GitHub Actions Workflow

Trigger via workflow_dispatch:
1. Go to nclaw/.github/workflows/release-cascade.yml
2. Click "Run workflow"
3. Enter version: `1.1.1`
4. Click "Run workflow"

The workflow will:
1. Run release gate (fails if conditions unmet)
2. Bump versions (commits to main)
3. Tag staging (smoke tests)
4. Tag production (point of no return)
5. Announce (changelog)
6. Publish all (npm, crates, mobile, docker, homebrew)
7. Verify (48h soak + audit log)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Gate fails on "stray root .md" | Run `/cleanup` to migrate files to .github/wiki/ or .claude/docs/ |
| SPORT count < 10 | Ensure all F01-F15 files committed; regenerate via SPORT generation |
| Version consistency mismatch | Run version-bump-cascade.sh to atomically update all |
| npm publish fails | Check NPM_TOKEN in GitHub secrets + npm registry auth |
| crates.io publish fails | Check CARGO_REGISTRY_TOKEN + Rust package dependencies |
| Docker push fails | Login to Docker Hub; verify credentials in secrets |
| Vercel verification stalls | Check VERCEL_TOKEN; verify team scope (unity-dev) |
| Tag already exists | Delete local tag: `git tag -d v1.1.1`; push deletion: `git push origin :refs/tags/v1.1.1` |

## Post-Release (48h Window)

After prod tag:
1. Monitor error rates (< 0.1%)
2. Check license validation latency (< 100ms p99)
3. Verify all deployments (Vercel, Hetzner, App Stores)
4. Monitor GitHub Actions CI (100% green)
5. Scan social/support channels for critical issues

If CRITICAL issue found: use rollback runbook (see operations docs).

## See Also

- `release-runbook.md` — step-by-step operator instructions
- `.claude/docs/operations/release-runbook.md` — detailed operational guide
- `.claude/planning/94-RELEASE-PLAN.md` — release planning (v1.0.9)
