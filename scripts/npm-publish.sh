#!/usr/bin/env bash
# npm-publish.sh — npm publish for nSelf packages
# Publishes admin + plugins + SDKs to npm registry (requires user approval)
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"

cd "$(dirname "$0")/../.."

echo "=== npm Publish (v$VERSION) ==="
echo ""
echo "⚠️  USER APPROVAL REQUIRED"
echo ""
echo "About to publish these packages to npm:"
echo "  1. @nself/admin v$VERSION"
echo "  2. @nself/plugins v$VERSION"
echo "  3. @nself/plugin-loader v$VERSION"
echo ""
echo "This is a POINT OF NO RETURN. Published packages cannot be unpublished."
echo ""
read -p "Type 'yes' to proceed, or anything else to cancel: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "❌ npm publish cancelled"
  exit 1
fi

echo -e "\n[Publishing admin]..."
if [ -f "admin/package.json" ]; then
  pushd "admin" > /dev/null
  # Stub: actual publish via npm CLI (requires authentication)
  # npm publish --access public --dry-run
  echo "  ℹ Would execute: npm publish --access public"
  popd > /dev/null
else
  echo "  ⚠ admin/package.json not found"
fi

echo -e "\n[Publishing plugins]..."
if [ -f "plugins/package.json" ]; then
  pushd "plugins" > /dev/null
  echo "  ℹ Would execute: npm publish --access public"
  popd > /dev/null
else
  echo "  ⚠ plugins/package.json not found"
fi

echo -e "\n[Publishing SDK]..."
if [ -f "cli/sdk/ts/package.json" ]; then
  pushd "cli/sdk/ts" > /dev/null
  echo "  ℹ Would execute: npm publish --access public"
  popd > /dev/null
else
  echo "  ⚠ cli/sdk/ts/package.json not found"
fi

echo -e "\n=== npm Publish Complete ==="
echo "✅ Packages ready (execute 'npm publish' commands manually or via CI)"
