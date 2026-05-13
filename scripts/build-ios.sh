#!/usr/bin/env bash
# build-ios.sh — Build libnclaw as an .xcframework for iOS device + simulator.
#
# Usage:
#   ./scripts/build-ios.sh
#
# Outputs:
#   mobile/ios/libnclaw.xcframework
#
# Prerequisites:
#   - Rust targets: aarch64-apple-ios + aarch64-apple-ios-sim
#     Install via: rustup target add aarch64-apple-ios aarch64-apple-ios-sim
#   - Xcode command-line tools (xcodebuild, lipo)
#   - cbindgen (optional, for header regeneration):
#     Install via: cargo install cbindgen
#
# The resulting .xcframework bundles both slices so Xcode automatically
# picks the correct slice for device builds vs Simulator runs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_MANIFEST="$REPO_ROOT/core/Cargo.toml"
INCLUDE_DIR="$REPO_ROOT/core/include"
OUTPUT="$REPO_ROOT/mobile/ios/libnclaw.xcframework"

echo "[build-ios] Building libnclaw for iOS device (aarch64-apple-ios)..."
cargo build --release \
  --target aarch64-apple-ios \
  --manifest-path "$CORE_MANIFEST"

echo "[build-ios] Building libnclaw for iOS Simulator (aarch64-apple-ios-sim)..."
cargo build --release \
  --target aarch64-apple-ios-sim \
  --manifest-path "$CORE_MANIFEST"

# Remove stale xcframework before recreating — xcodebuild will fail otherwise.
if [ -d "$OUTPUT" ]; then
  echo "[build-ios] Removing stale xcframework at $OUTPUT"
  rm -rf "$OUTPUT"
fi

echo "[build-ios] Creating .xcframework..."
xcodebuild -create-xcframework \
  -library "$REPO_ROOT/core/target/aarch64-apple-ios/release/libnclaw.a" \
  -headers "$INCLUDE_DIR" \
  -library "$REPO_ROOT/core/target/aarch64-apple-ios-sim/release/libnclaw.a" \
  -headers "$INCLUDE_DIR" \
  -output "$OUTPUT"

echo "[build-ios] Done. Built: $OUTPUT"
