#!/usr/bin/env bash
# announce.sh — announcement + changelog generation for P101 v1.1.1
# Updates CHANGELOG.md and announces release across channels
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"

cd "$(dirname "$0")/../.."

echo "=== Release Announcement (v$VERSION) ==="

# Generate changelog entry (stub)
CHANGELOG_ENTRY="## [v$VERSION] - $(date -u +'%Y-%m-%d')

### Added
- nClaw monorepo with Tauri 2 desktop + Flutter mobile + Rust core (libnclaw)
- ɳSentry observability plugin bundle (7 plugins)
- ɳFamily social product (PLANNED v1.1.0)
- ClawDE v1.0 stable release
- Full nSelf-First doctrine compliance

### Changed
- Simplified pricing: all bundles \$0.99/mo, ɳSelf+ \$3.99/mo or \$39.99/yr
- Admin + CLI version lockstep (v1.0.x consistent)
- Plugin licensing system unified

### Fixed
- OS admin prompt idempotency (no more prompt bursts)
- GitHub Actions CI 100% green enforcement
- Multi-tenant convention wall (no data leaks)

### Deprecated
- nMedia bundle renamed to ɳTV bundle

For full details, see UPGRADE.md and MIGRATION.md in each repo."

# Append to main CHANGELOG (if it exists at project level)
if [ -f ".claude/docs/archive/CHANGELOG.md" ]; then
  echo "  Updating .claude/docs/archive/CHANGELOG.md..."
  {
    echo "$CHANGELOG_ENTRY"
    echo ""
    cat ".claude/docs/archive/CHANGELOG.md"
  } > ".claude/docs/archive/CHANGELOG.md.new" && mv ".claude/docs/archive/CHANGELOG.md.new" ".claude/docs/archive/CHANGELOG.md"
  echo "  ✓ CHANGELOG updated"
fi

# Announcement template
ANNOUNCE_TEXT="🚀 **nSelf v$VERSION Released**

**Highlights:**
- nClaw v1.1.1: Tauri 2 desktop, Flutter mobile, Rust core with infinite memory
- ɳSentry observability bundle: 7 plugins for production monitoring
- Simplified pricing: all bundles \$0.99/mo, ɳSelf+ \$3.99/mo or \$39.99/yr
- 100% nSelf-First compliance: no side-channel Docker compose

**Download:**
- macOS: \`brew upgrade nself\`
- Web: nself.org/install
- Docker: \`docker pull nself/nself-admin:$VERSION\`

**Links:**
- GitHub: github.com/nself-org
- Docs: docs.nself.org
- Support: chat.nself.org

Thanks to the community. 🙏"

echo -e "\n=== Announcement Text ==="
echo "$ANNOUNCE_TEXT"

echo -e "\n=== Announcement Channels ==="
echo "  ℹ Would post to:"
echo "    - Twitter / X (@nself_org)"
echo "    - Discord #announcements"
echo "    - nself.org/changelog"
echo "    - GitHub Discussions"
echo "    - Product Hunt (optional)"

echo -e "\n=== Release Announcement Complete ==="
echo "✅ Announcement ready (manual posting recommended)"
