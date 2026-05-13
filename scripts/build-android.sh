#!/usr/bin/env bash
# build-android.sh — Build libnclaw .so libraries for Android ABIs via cargo-ndk.
#
# Usage:
#   ./scripts/build-android.sh
#
# Outputs:
#   mobile/android/app/src/main/jniLibs/arm64-v8a/libnclaw.so
#   mobile/android/app/src/main/jniLibs/armeabi-v7a/libnclaw.so
#
# Prerequisites:
#   - Android NDK installed and ANDROID_NDK_HOME set (or NDK in SDK path)
#   - cargo-ndk: cargo install cargo-ndk
#   - Rust targets:
#       rustup target add aarch64-linux-android armv7-linux-androideabi
#
# Gradle picks up the .so files automatically because they live under
# app/src/main/jniLibs — no additional CMake or build.gradle changes needed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_MANIFEST="$REPO_ROOT/core/Cargo.toml"
JNI_DIR="$REPO_ROOT/mobile/android/app/src/main/jniLibs"

echo "[build-android] Creating jniLibs directories..."
mkdir -p "$JNI_DIR/arm64-v8a"
mkdir -p "$JNI_DIR/armeabi-v7a"

echo "[build-android] Building libnclaw for Android (arm64-v8a + armeabi-v7a)..."
cargo ndk \
  --target aarch64-linux-android \
  --target armv7-linux-androideabi \
  --manifest-path "$CORE_MANIFEST" \
  --output-dir "$JNI_DIR" \
  build --release

echo "[build-android] Done. Built Android jniLibs at $JNI_DIR"
ls -lh "$JNI_DIR/arm64-v8a/" "$JNI_DIR/armeabi-v7a/" 2>/dev/null || true
