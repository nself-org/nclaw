#!/usr/bin/env bash
# crates-io-publish.sh — publish Rust crates to crates.io
# nclaw-core + nclaw-protocol → crates.io
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"

cd "$(dirname "$0")/../.."

echo "=== Crates.io Publish (v$VERSION) ==="

# Require cargo
if ! command -v cargo &>/dev/null; then
  echo "⚠ cargo not found; skipping crates.io publish"
  exit 0
fi

# nclaw-core
echo -e "\n[nclaw-core]"
if [ -f "nclaw/crates/nclaw-core/Cargo.toml" ]; then
  echo "  Publishing nclaw-core v$VERSION to crates.io..."
  pushd "nclaw/crates/nclaw-core" > /dev/null
  echo "  ℹ Would execute: cargo publish --allow-dirty (stub)"
  # cargo publish --token "$CARGO_REGISTRY_TOKEN"
  popd > /dev/null
else
  echo "  ⚠ nclaw-core/Cargo.toml not found"
fi

# nclaw-protocol
echo -e "\n[nclaw-protocol]"
if [ -f "nclaw/crates/nclaw-protocol/Cargo.toml" ]; then
  echo "  Publishing nclaw-protocol v$VERSION to crates.io..."
  pushd "nclaw/crates/nclaw-protocol" > /dev/null
  echo "  ℹ Would execute: cargo publish --allow-dirty (stub)"
  popd > /dev/null
else
  echo "  ⚠ nclaw-protocol/Cargo.toml not found"
fi

# libnclaw (Rust core, FFI)
echo -e "\n[libnclaw]"
if [ -f "nclaw/libs/libnclaw/Cargo.toml" ]; then
  echo "  Publishing libnclaw v$VERSION to crates.io..."
  pushd "nclaw/libs/libnclaw" > /dev/null
  echo "  ℹ Would execute: cargo publish (stub)"
  popd > /dev/null
else
  echo "  ⚠ libnclaw/Cargo.toml not found (may be internal only)"
fi

echo -e "\n=== Crates.io Publish Complete ==="
echo "✅ Crates ready (execute 'cargo publish' manually or via CI)"
