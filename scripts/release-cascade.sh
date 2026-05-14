#!/usr/bin/env bash
# release-cascade.sh — orchestrator for P101 v1.1.1 release
# Coordinates version bump, staging tag, smoke tests, prod tag, and announcements
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
STEP="${2:-all}"  # all, gate, bump, staging, smoke, prod, announce, publish

cd "$(dirname "$0")/../.."

echo "=== nSelf Release Cascade Orchestrator ==="
echo "Version: v$VERSION"
echo "Step: $STEP"

case "$STEP" in
  gate|all)
    echo -e "\n[Step 1/7] Release Gate"
    bash nclaw/scripts/release-gate.sh
    [ "$STEP" = "gate" ] && exit 0
    ;;
esac

case "$STEP" in
  bump|all)
    echo -e "\n[Step 2/7] Version Bump Cascade"
    bash nclaw/scripts/version-bump-cascade.sh "$VERSION"
    [ "$STEP" = "bump" ] && exit 0
    ;;
esac

case "$STEP" in
  staging|all)
    echo -e "\n[Step 3/7] Staging Tag + Build"
    bash nclaw/scripts/prod-tag.sh "$VERSION" --staging-only
    [ "$STEP" = "staging" ] && exit 0
    ;;
esac

case "$STEP" in
  smoke|all)
    echo -e "\n[Step 4/7] Staging Smoke Tests"
    bash nclaw/scripts/staging-smoke.sh "$VERSION"
    [ "$STEP" = "smoke" ] && exit 0
    ;;
esac

case "$STEP" in
  prod|all)
    echo -e "\n[Step 5/7] Production Tag + Release"
    bash nclaw/scripts/prod-tag.sh "$VERSION" --prod
    [ "$STEP" = "prod" ] && exit 0
    ;;
esac

case "$STEP" in
  announce|all)
    echo -e "\n[Step 6/7] Announce + Changelog"
    bash nclaw/scripts/announce.sh "$VERSION"
    [ "$STEP" = "announce" ] && exit 0
    ;;
esac

case "$STEP" in
  publish|all)
    echo -e "\n[Step 7/7] Publish (npm, crates, mobile, homebrew)"
    bash nclaw/scripts/npm-publish.sh "$VERSION"
    bash nclaw/scripts/sdk-publish.sh "$VERSION"
    bash nclaw/scripts/crates-io-publish.sh "$VERSION"
    bash nclaw/scripts/homebrew-sync.sh "$VERSION"
    bash nclaw/scripts/docker-build-push.sh "$VERSION"
    echo -e "\n✅ Release cascade complete: v$VERSION"
    ;;
esac
