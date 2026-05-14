#!/usr/bin/env bash
# prod-tag.sh — prod tag + GitHub Releases for P101 v1.1.1
# Creates annotated git tags and GitHub Releases for all 12 repos
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
MODE="${2:---prod}"  # --staging-only or --prod

cd "$(dirname "$0")/../.."
REPOS=(cli admin plugins plugins-pro nchat nclaw ntask ntv nfamily clawde web homebrew-nself)

echo "=== Production Tag & Releases (v$VERSION) ==="
echo "Mode: $MODE"

TAGGED=0
for repo in "${REPOS[@]}"; do
  if [ ! -d "$repo" ]; then
    echo "  SKIP: $repo (not found)"
    continue
  fi

  pushd "$repo" > /dev/null
  CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "none")

  if [ "$CURRENT_TAG" = "v$VERSION" ]; then
    echo "  $repo: already tagged v$VERSION, skipping"
    popd > /dev/null
    continue
  fi

  echo -e "\n  [$repo] Creating tag v$VERSION"

  # Annotated tag
  TAG_MSG="Release v$VERSION

Platform: nSelf Ecosystem
Component: $repo
Date: $(date -u +'%Y-%m-%dT%H:%M:%SZ')
Phase: P101 S23 Release Cascade"

  git tag -a "v$VERSION" -m "$TAG_MSG" || {
    echo "    ✗ Tag creation failed (tag may exist)"
    popd > /dev/null
    continue
  }

  TAGGED=$((TAGGED+1))

  # GitHub Release (requires gh CLI)
  if command -v gh &>/dev/null && [ "$MODE" != "--staging-only" ]; then
    RELEASE_BODY="### Release v$VERSION

**Ecosystem Component:** $repo
**Date:** $(date -u +'%Y-%m-%d %H:%M UTC')

See CHANGELOG.md for details.

**Installation:**
- macOS: \`brew upgrade nself\` (if applicable)
- GitHub Release: artifacts below
- npm registry (if applicable): \`npm install @nself/$repo@$VERSION\`"

    echo "    Creating GitHub Release..."
    gh release create "v$VERSION" \
      --title "v$VERSION" \
      --notes "$RELEASE_BODY" \
      --repo "nself-org/$repo" 2>/dev/null || {
      echo "    ⚠ GitHub Release creation skipped or failed"
    }
  fi

  popd > /dev/null
done

echo -e "\n=== Tag Summary ==="
echo "Tags created: $TAGGED"
echo "Mode: $MODE"
[ "$MODE" = "--staging-only" ] && echo "ℹ Staging mode: tags created, releases deferred until --prod"
echo "✅ Production tagging complete"
