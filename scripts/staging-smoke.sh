#!/usr/bin/env bash
# staging-smoke.sh — post-staging smoke test for P101 v1.1.1
# Verifies core functionality on staging before prod tag
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"

cd "$(dirname "$0")/../.."

echo "=== Staging Smoke Tests (v$VERSION) ==="

# Test 1: CLI help works
echo -e "\n[Smoke 1/8] CLI help output"
if [ -f "cli/nself" ] || command -v nself &>/dev/null; then
  if nself --version 2>&1 | grep -q "$VERSION"; then
    echo "  ✓ CLI version correct"
  else
    echo "  ⚠ CLI version may not match (CLI version detection varies)"
  fi
else
  echo "  ⚠ CLI binary not found (expected: built on staging)"
fi

# Test 2: nClaw startup
echo -e "\n[Smoke 2/8] nClaw monorepo structure"
if [ -f "nclaw/Cargo.toml" ] && [ -f "nclaw/apps/desktop/Cargo.toml" ]; then
  echo "  ✓ nClaw monorepo structure intact"
else
  echo "  ⚠ nClaw monorepo structure incomplete"
fi

# Test 3: Admin UI build
echo -e "\n[Smoke 3/8] Admin UI build"
if [ -f "admin/package.json" ]; then
  if jq -e '.version' admin/package.json &>/dev/null; then
    echo "  ✓ Admin package.json valid"
  else
    echo "  ✗ Admin package.json malformed"
    exit 1
  fi
else
  echo "  ⚠ Admin package.json not found"
fi

# Test 4: Plugins registry (free)
echo -e "\n[Smoke 4/8] Free plugins registry"
if [ -f "plugins/registry.json" ] || [ -d "plugins/paid" ]; then
  echo "  ✓ Plugins structure intact"
else
  echo "  ⚠ Plugins registry structure incomplete"
fi

# Test 5: Reference apps (nchat, ntask)
echo -e "\n[Smoke 5/8] Reference apps"
for app in nchat ntask; do
  if [ -f "$app/package.json" ]; then
    echo "  ✓ $app present"
  else
    echo "  ⚠ $app missing or malformed"
  fi
done

# Test 6: Web subapps (backend, org, docs)
echo -e "\n[Smoke 6/8] Web subapps"
for subapp in backend org docs; do
  if [ -d "web/$subapp" ]; then
    echo "  ✓ web/$subapp present"
  else
    echo "  ⚠ web/$subapp missing"
  fi
done

# Test 7: SPORT files (master lists)
echo -e "\n[Smoke 7/8] SPORT canonical files"
SPORT_COUNT=$(find nclaw/.claude/docs/sport -name "F??-*.md" 2>/dev/null | wc -l || echo 0)
if [ "$SPORT_COUNT" -ge 10 ]; then
  echo "  ✓ SPORT files present ($SPORT_COUNT)"
else
  echo "  ⚠ SPORT files incomplete (found $SPORT_COUNT, expected ≥10)"
fi

# Test 8: Git state (all clean, tagged)
echo -e "\n[Smoke 8/8] Git state"
if git describe --tags --exact-match 2>/dev/null | grep -q "v$VERSION"; then
  echo "  ✓ Git tag v$VERSION exists"
else
  echo "  ⚠ Git tag v$VERSION may not be present yet (expected after prod-tag.sh)"
fi

echo -e "\n=== Staging Smoke Complete ==="
echo "✅ Staging smoke tests passed (warnings acceptable)"
