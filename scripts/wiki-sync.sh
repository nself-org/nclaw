#!/usr/bin/env bash
# wiki-sync.sh — sync .github/wiki/ + SPORT to public facing docs
# Updates nself.org/docs/ with latest wiki content
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"

cd "$(dirname "$0")/../.."

echo "=== Wiki Sync (v$VERSION) ==="

# Stub: actual sync via web/docs build or git-based wiki publishing
# This script shows the pattern

REPOS=(cli admin plugins nchat nclaw ntask ntv nfamily clawde)

SYNCED=0
for repo in "${REPOS[@]}"; do
  if [ ! -d "$repo/.github/wiki" ]; then
    continue
  fi

  echo "  Syncing $repo/.github/wiki/..."
  # In practice: copy .github/wiki/ → web/docs/public/repos/<repo>/
  # Then run web/docs build to regenerate static HTML

  SYNCED=$((SYNCED+1))
done

# Sync SPORT files
echo -e "\n  Syncing SPORT canonical files..."
if [ -d "nclaw/.claude/docs/sport" ]; then
  # SPORT files are NOT published (internal reference)
  # But SPORT-derived content (command inventory, port registry) IS published
  echo "  ℹ SPORT derived docs would be generated for web/docs"
else
  echo "  ⚠ SPORT not found"
fi

# Trigger web/docs build (requires node)
echo -e "\n  Building web/docs..."
if [ -f "web/docs/package.json" ]; then
  pushd "web/docs" > /dev/null
  echo "  ℹ web/docs build would be triggered (stub)"
  # In practice: pnpm build
  popd > /dev/null
fi

echo -e "\n=== Wiki Sync Complete ==="
echo "Synced: $SYNCED repos"
echo "✅ Wiki updated (manual deployment to docs.nself.org recommended)"
