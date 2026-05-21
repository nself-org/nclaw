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
#
# Notes:
#   - core/ is a workspace member, so cargo writes artifacts to the workspace
#     target dir at the repo root, not core/target/.
#   - The crate is named "libnclaw"; cargo prefixes the staticlib with "lib",
#     producing liblibnclaw.a.
#   - The mobile-static profile (root Cargo.toml) disables LTO so the
#     #[no_mangle] C-ABI exports survive dead-code elimination.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_MANIFEST="$REPO_ROOT/core/Cargo.toml"
INCLUDE_DIR="$REPO_ROOT/core/include"
OUTPUT="$REPO_ROOT/mobile/ios/libnclaw.xcframework"
PROFILE="mobile-static"
# cargo's --profile name maps to a same-named target subdir, except "release"
# which uses "release"; mobile-static -> target/<triple>/mobile-static/.
PROFILE_DIR="$PROFILE"
DEVICE_TRIPLE="aarch64-apple-ios"
SIM_TRIPLE="aarch64-apple-ios-sim"
STATICLIB="liblibnclaw.a"

echo "[build-ios] Building libnclaw for iOS device ($DEVICE_TRIPLE)..."
cargo build --profile "$PROFILE" \
  --target "$DEVICE_TRIPLE" \
  --manifest-path "$CORE_MANIFEST"

echo "[build-ios] Building libnclaw for iOS Simulator ($SIM_TRIPLE)..."
cargo build --profile "$PROFILE" \
  --target "$SIM_TRIPLE" \
  --manifest-path "$CORE_MANIFEST"

DEVICE_LIB="$REPO_ROOT/target/$DEVICE_TRIPLE/$PROFILE_DIR/$STATICLIB"
SIM_LIB="$REPO_ROOT/target/$SIM_TRIPLE/$PROFILE_DIR/$STATICLIB"

for lib in "$DEVICE_LIB" "$SIM_LIB"; do
  if [ ! -f "$lib" ]; then
    echo "[build-ios] ERROR: expected static library not found: $lib" >&2
    exit 1
  fi
done

# Sanity-check that the C-ABI exports survived the build before packaging.
# nm exits non-zero when the archive holds objects with no symbols (it still
# prints every symbol it finds), and piping it straight into `grep -q` lets
# grep close the pipe on first match and SIGPIPE nm. Both interact badly with
# `set -o pipefail`, so dump to a temp file and grep that instead.
nm_dump="$(mktemp)"
trap 'rm -f "$nm_dump"' EXIT
xcrun nm "$DEVICE_LIB" >"$nm_dump" 2>/dev/null || true
if ! grep -q "nclaw_set_low_power" "$nm_dump"; then
  echo "[build-ios] ERROR: nclaw_set_low_power missing from $DEVICE_LIB" >&2
  echo "[build-ios] The mobile-static profile must keep LTO disabled." >&2
  exit 1
fi

# Remove stale xcframework before recreating — xcodebuild will fail otherwise.
if [ -d "$OUTPUT" ]; then
  echo "[build-ios] Removing stale xcframework at $OUTPUT"
  rm -rf "$OUTPUT"
fi

echo "[build-ios] Creating .xcframework..."
xcodebuild -create-xcframework \
  -library "$DEVICE_LIB" \
  -headers "$INCLUDE_DIR" \
  -library "$SIM_LIB" \
  -headers "$INCLUDE_DIR" \
  -output "$OUTPUT"

echo "[build-ios] Done. Built: $OUTPUT"
