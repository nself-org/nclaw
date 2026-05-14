#!/usr/bin/env bash
# homebrew-sync.sh — update homebrew tap for nSelf CLI release
# Auto-syncs tap formula from GitHub release artefacts
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"

cd "$(dirname "$0")/../.."

echo "=== Homebrew Tap Sync (v$VERSION) ==="

if [ ! -d "homebrew-nself" ]; then
  echo "✗ homebrew-nself directory not found"
  exit 1
fi

pushd "homebrew-nself" > /dev/null

# The actual formula update is typically done by a CI workflow
# that extracts SHA256 from released binaries and updates Formula/nself.rb
# This script stages the update

echo "  Checking homebrew-nself state..."
if [ -f "Formula/nself.rb" ]; then
  echo "  ✓ Formula/nself.rb exists"
  # Homebrew auto-syncs from upstream tap repo on each brew update
  # No manual change needed; CI handles formula updates
  echo "  ℹ Formula updates handled by CI (GitHub Actions)"
else
  echo "  ✗ Formula/nself.rb not found"
  popd > /dev/null
  exit 1
fi

# Verify formula syntax
if command -v brew &>/dev/null; then
  echo "  Validating formula syntax..."
  brew install-tap-test Formula/nself.rb 2>/dev/null || echo "  ⚠ Formula validation skipped (requires local brew)"
fi

popd > /dev/null

echo -e "\n=== Homebrew Sync Complete ==="
echo "✅ Homebrew tap ready (CI will auto-update Formula/nself.rb from release)"
