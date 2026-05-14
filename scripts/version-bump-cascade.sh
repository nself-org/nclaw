#!/usr/bin/env bash
# version-bump-cascade.sh — atomic version bump across all 12 repos
# Updates package.json, Cargo.toml, pubspec.yaml, go.mod as needed
set -euo pipefail

TARGET="${1:?Usage: $0 <version> (e.g., 1.1.1)}"
DRY_RUN="${2:-false}"

cd "$(dirname "$0")/../.."
REPOS=(cli admin plugins plugins-pro nchat nclaw ntask ntv nfamily clawde web homebrew-nself)

echo "=== Version Bump Cascade to v$TARGET ==="
[ "$DRY_RUN" = "true" ] && echo "[DRY RUN MODE]"

BUMPED=0
for repo in "${REPOS[@]}"; do
  if [ ! -d "$repo" ]; then
    echo "  SKIP: $repo (directory not found)"
    continue
  fi

  echo -e "\n[$repo]"
  pushd "$repo" > /dev/null

  # Go repos: cli, admin
  if [ -f "go.mod" ]; then
    CURRENT=$(grep '^module ' go.mod | awk '{print $2}' | head -1)
    echo "  go.mod: current module $CURRENT"
    if [ "$DRY_RUN" = "false" ]; then
      # Version embedded in main.go or similar; skip here (handled in per-repo build)
      echo "  → Version bump deferred to build time (go.mod tracks module path, not version)"
    fi
  fi

  # TypeScript/Node: admin, nchat, nclaw, ntask, web
  if [ -f "package.json" ]; then
    OLD_VERSION=$(jq -r '.version' package.json 2>/dev/null || echo "unknown")
    echo "  package.json: $OLD_VERSION → $TARGET"
    if [ "$DRY_RUN" = "false" ]; then
      jq ".version = \"$TARGET\"" package.json > package.json.tmp && mv package.json.tmp package.json
      BUMPED=$((BUMPED+1))
    fi
  fi

  # Rust: nclaw (core + protocol)
  if [ -f "Cargo.toml" ]; then
    OLD_VERSION=$(grep '^version' Cargo.toml | head -1 | awk -F'"' '{print $2}' || echo "unknown")
    echo "  Cargo.toml: $OLD_VERSION → $TARGET"
    if [ "$DRY_RUN" = "false" ]; then
      sed -i.bak "s/^version = \"[^\"]*\"/version = \"$TARGET\"/" Cargo.toml && rm -f Cargo.toml.bak
      BUMPED=$((BUMPED+1))
    fi
  fi

  # Flutter: ntv, nfamily
  if [ -f "pubspec.yaml" ]; then
    OLD_VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' || echo "unknown")
    echo "  pubspec.yaml: $OLD_VERSION → $TARGET"
    if [ "$DRY_RUN" = "false" ]; then
      sed -i.bak "s/^version: [0-9.+]*/version: $TARGET/" pubspec.yaml && rm -f pubspec.yaml.bak
      BUMPED=$((BUMPED+1))
    fi
  fi

  # Homebrew: special case (version in formula, not auto-synced)
  if [ "$repo" = "homebrew-nself" ] && [ -f "Formula/nself.rb" ]; then
    echo "  Formula/nself.rb: Homebrew will auto-sync from GitHub release"
  fi

  popd > /dev/null
done

echo -e "\n=== Version Bump Summary ==="
echo "Target version: v$TARGET"
echo "Files bumped: $BUMPED"
[ "$DRY_RUN" = "true" ] && echo "DRY RUN — no changes written"
echo "✅ Version bump cascade complete"
