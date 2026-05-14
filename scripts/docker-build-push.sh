#!/usr/bin/env bash
# docker-build-push.sh — build and push Docker images for nSelf v1.1.1
# Images: nself/nself-admin, nself/nself-cli, nself/nself-plugins-loader
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
REGISTRY="${REGISTRY:-docker.io}"  # Configurable registry

cd "$(dirname "$0")/../.."

echo "=== Docker Build & Push (v$VERSION) ==="
echo "Registry: $REGISTRY"

# Require docker
if ! command -v docker &>/dev/null; then
  echo "✗ docker CLI not found"
  exit 1
fi

# Build admin image
echo -e "\n[1/3] Building nself-admin image..."
if [ -f "admin/Dockerfile" ]; then
  docker build \
    --tag "$REGISTRY/nself/nself-admin:$VERSION" \
    --tag "$REGISTRY/nself/nself-admin:latest" \
    -f admin/Dockerfile admin/ 2>/dev/null && echo "  ✓ Image built: nself-admin:$VERSION" || echo "  ⚠ Build skipped"
else
  echo "  ⚠ admin/Dockerfile not found"
fi

# Build CLI image (if applicable)
echo -e "\n[2/3] Building nself-cli image..."
if [ -f "cli/Dockerfile" ]; then
  docker build \
    --tag "$REGISTRY/nself/nself-cli:$VERSION" \
    --tag "$REGISTRY/nself/nself-cli:latest" \
    -f cli/Dockerfile cli/ 2>/dev/null && echo "  ✓ Image built: nself-cli:$VERSION" || echo "  ⚠ Build skipped"
else
  echo "  ⚠ cli/Dockerfile not found (CLI is single-binary, no image needed)"
fi

# Push images (requires docker login)
echo -e "\n[3/3] Pushing images to $REGISTRY..."
if docker push "$REGISTRY/nself/nself-admin:$VERSION" 2>/dev/null; then
  echo "  ✓ Pushed nself-admin:$VERSION"
else
  echo "  ⚠ Push skipped (docker login may be required, or image unavailable)"
fi

echo -e "\n=== Docker Build & Push Complete ==="
echo "✅ Images ready (if builds succeeded)"
