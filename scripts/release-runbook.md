# Release Runbook — nSelf v1.1.1

**Duration:** ~3 hours (wall clock with 48h soak)  
**Operator:** Release manager + on-call team  
**Risk level:** Critical — affects production  

## Pre-Release Checklist (Day -1)

- [ ] All PRs merged, main green for 48h
- [ ] S0-S22 exit criteria verified in CHECKLIST.md
- [ ] Staging environment tested (admin, cli, plugins)
- [ ] CI/CD 100% green across all 12 repos
- [ ] Release notes drafted
- [ ] Social media announcements queued
- [ ] Support team notified (response plan ready)
- [ ] Rollback runbook reviewed
- [ ] Database migrations tested on staging
- [ ] License validation service (ping_api) staged

## Release Day — Step by Step

### Step 1: Release Gate (10 min)
```bash
cd /Volumes/X9/Sites/nself
bash nclaw/scripts/release-gate.sh
```
Expected: "RELEASE GATE PASSED"

If fails: resolve blockers, fix code, re-run gate.

### Step 2: Version Bump (5 min)
```bash
bash nclaw/scripts/release-cascade.sh 1.1.1 bump
```
Updates:
- cli: go.mod version in main.go
- admin: package.json
- plugins: package.json
- plugins-pro: package.json
- nchat, nclaw, ntask, ntv, nfamily, clawde: package.json + Cargo.toml (nclaw)
- web: package.json
- homebrew-nself: Formula/nself.rb (auto-synced)

Check: `git diff --stat`

### Step 3: Staging Tag (15 min)
```bash
bash nclaw/scripts/release-cascade.sh 1.1.1 staging
```
Creates lightweight tags + runs staging smoke tests.

Expected: All smoke tests pass. Resolve any failures before proceeding.

### Step 4: Staging Soak (30 min)
Manual verification on staging:
```bash
# SSH to staging: 167.235.233.65 (nself-staging)
nself version  # should show 1.1.1
nself admin start  # admin UI at localhost:3021
nself license validate nself_pro_xxxx  # test license validation
```

Run quick end-to-end test:
- Create a test plugin
- Verify license checks work
- Verify database migrations applied
- Spot-check error logs

### Step 5: Production Tag — **POINT OF NO RETURN** (10 min)
```bash
bash nclaw/scripts/release-cascade.sh 1.1.1 prod
```
Creates annotated tags + GitHub Releases for all 12 repos.

**After this step, binaries are immutable. Undo only via rollback.**

### Step 6: Announce (5 min)
```bash
bash nclaw/scripts/announce.sh 1.1.1
```
Generates changelog. Manually post to:
- [ ] Twitter / X
- [ ] Discord #announcements
- [ ] nself.org/changelog
- [ ] GitHub Discussions

### Step 7: Publish (60 min, parallel)
```bash
bash nclaw/scripts/release-cascade.sh 1.1.1 publish
```

Each publish requires approval. Commands:
- npm publish (requires NPM_TOKEN)
- cargo publish (requires CARGO_REGISTRY_TOKEN)
- docker push (requires Docker Hub login)
- homebrew sync (auto from release)
- mobile submit (requires App Store + Play Store auth)

**Monitor each publish for errors. Rollback if critical failure.**

### Step 8: Bundle Smoke (10 min)
```bash
bash nclaw/scripts/bundle-smoke.sh 1.1.1
```
Verifies:
- CLI works (`nself --version`)
- Admin Docker image pulls
- npm packages exist
- SDKs available in registries

### Step 9: 48-Hour Soak (Start monitoring)
```bash
bash nclaw/scripts/soak-48h.sh 1.1.1
```
Monitor dashboard:
- Grafana: nself.org/grafana (production metrics)
- Vercel: vercel.com (deployments)
- GitHub: github.com/nself-org (CI/CD)
- Sentry: sentry.io (error tracking)

Alert conditions (halt if triggered):
- Error rate > 1%
- License validation failures
- API latency > 5s p99
- Database connection failures
- OOM/crash on any service

### Step 10: Audit Log Sign
```bash
bash nclaw/scripts/audit-log-sign.sh 1.1.1
```
Records release event + cryptographic signature.

## Post-Release (48h Window)

### Hour 0–6: Critical Monitoring
- Refresh Grafana every 30 min
- Monitor Slack #incidents for alerts
- Check GitHub Actions for red runs
- Scan Twitter/Discord for user reports

### Hour 6–24: Extended Monitoring
- Monitor for edge cases
- Verify all app stores accept submission
- Spot-check newly registered users
- Review support tickets

### Hour 24–48: Soak Completion
- Verify stability metrics
- Check database size growth
- Confirm no cascading issues
- Sign off soak test

## If Critical Issue Found

**During soak (48h window):**

1. Create incident report
2. Evaluate issue severity
3. If CRITICAL (data loss / security / total unavailability):
   - Trigger rollback runbook
   - Revert to v1.0.13
   - Document root cause
4. If HIGH (major degradation):
   - Create hotfix PR
   - Deploy patch v1.1.2 to staging
   - Run smoke + mini-soak
   - Deploy to production
5. If MEDIUM (minor issue):
   - Log for next patch
   - Continue monitoring

**Rollback command (use only for CRITICAL):**
```bash
bash .claude/docs/operations/rollback-runbook.sh 1.0.13
```

## Sign-Off Checklist (after 48h)

- [ ] Error rate nominal (< 0.1%)
- [ ] No security incidents
- [ ] All app stores accepted
- [ ] License validation working
- [ ] User feedback positive
- [ ] No cascading failures
- [ ] Database health good
- [ ] Soak test audit log signed

## Release Complete

Send completion report to user:
```
✅ nSelf v1.1.1 RELEASED

Deployed:
  - CLI: homebrew, GitHub Releases
  - Admin: Docker Hub nself/nself-admin:1.1.1
  - Plugins: npm @nself/plugins@1.1.1
  - SDKs: npm, PyPI, crates.io, pub.dev
  - Mobile: App Store, Google Play
  - Web: Vercel (nself.org + subdomains)

Soak test: PASSED (48h clean)
Status: STABLE

Users can now upgrade via:
  brew upgrade nself
  nself license validate nself_pro_...
  npm install @nself/admin@1.1.1
```

## Escalation Path

| Issue | Escalation | Action |
|-------|-----------|--------|
| Gate fails | Stop immediately | Fix S0-S22 criteria |
| Publish fails | 30min window | Retry via CI or manual |
| Soak CRITICAL | Alert on-call | Trigger rollback |
| Soak HIGH | Create hotfix | Patch v1.1.2 |
| Soak MEDIUM | Log for later | Continue monitoring |

## See Also

- Release Cascade Architecture: `.github/wiki/release-cascade.md`
- Rollback Runbook: `.claude/docs/operations/rollback-runbook.md`
- CI/CD Green Rule: `.claude/docs/doctrines/ci-cd-green.md`
- nSelf-First Doctrine: `.claude/docs/doctrines/nself-first.md`
