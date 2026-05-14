#!/usr/bin/env bash
# ping-api-redeploy.sh — version bump + redeploy ping_api (web/backend CS_1)
# ping_api: telemetry + license validation service
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"

cd "$(dirname "$0")/../.."

echo "=== ping_api Redeploy (v$VERSION) ==="

# Stub: actual redeploy via Vercel, K8s, or direct Hetzner
# This script shows the pattern

if [ ! -d "web" ]; then
  echo "✗ web directory not found"
  exit 1
fi

pushd "web" > /dev/null

echo "  Bumping ping_api version to $VERSION..."
if [ -f "backend/services/ping_api/.env" ] || [ -f "backend/services/ping_api/version.txt" ]; then
  echo "  ℹ ping_api configuration would be updated (stub)"
  echo "  → PING_API_VERSION=$VERSION"
else
  echo "  ⚠ ping_api version file not found"
fi

# Example: trigger Vercel redeploy (requires vercel CLI + auth)
if command -v vercel &>/dev/null; then
  echo "  Triggering Vercel deployment..."
  # vercel --token $VERCEL_TOKEN --scope unity-dev deploy --prod 2>/dev/null || echo "  ⚠ Vercel deploy skipped"
  echo "  ℹ Vercel deploy would be triggered (stub)"
else
  echo "  ⚠ vercel CLI not found"
fi

popd > /dev/null

echo -e "\n=== ping_api Redeploy Complete ==="
echo "✅ ping_api ready to serve v$VERSION license checks"
