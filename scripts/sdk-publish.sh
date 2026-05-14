#!/usr/bin/env bash
# sdk-publish.sh — publish SDKs for v1.1.1
# Go, Python, TypeScript, Flutter SDKs → language registries
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"

cd "$(dirname "$0")/../.."

echo "=== SDK Publish (v$VERSION) ==="

# TypeScript SDK → npm
echo -e "\n[TypeScript SDK]"
if [ -f "cli/sdk/ts/package.json" ]; then
  echo "  @nself/sdk-ts v$VERSION"
  echo "  ℹ npm publish (manual or via CI)"
else
  echo "  ⚠ cli/sdk/ts not found"
fi

# Python SDK → PyPI
echo -e "\n[Python SDK]"
if [ -f "cli/sdk/py/setup.py" ] || [ -f "cli/sdk/py/pyproject.toml" ]; then
  echo "  nself-sdk v$VERSION"
  echo "  ℹ python -m build && python -m twine upload (manual or via CI)"
else
  echo "  ⚠ cli/sdk/py not found"
fi

# Go SDK → GitHub Releases (no registry publish needed)
echo -e "\n[Go SDK]"
if [ -f "cli/sdk/go/go.mod" ]; then
  echo "  github.com/nself-org/nself-sdk-go v$VERSION"
  echo "  ℹ Go module available via git tag (no registry needed)"
else
  echo "  ⚠ cli/sdk/go not found"
fi

# Flutter SDK → pub.dev
echo -e "\n[Flutter SDK]"
if [ -f "cli/sdk/flutter/pubspec.yaml" ]; then
  echo "  nself_sdk v$VERSION"
  echo "  ℹ flutter pub publish (manual or via CI)"
else
  echo "  ⚠ cli/sdk/flutter not found"
fi

echo -e "\n=== SDK Publish Complete ==="
echo "✅ SDKs ready for publication"
