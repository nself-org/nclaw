#!/usr/bin/env bash
set -euo pipefail

# Build sqlite-vec extension as static lib for 7 mobile triples.
# Real implementation lands in S16.T02b CI ticket.
# This script documents the build targets and process.

cat <<'EOF'
sqlite-vec multi-arch static-library build placeholder.

Purpose: Compile sqlite-vec (https://github.com/asg017/sqlite-vec) as static libraries
for iOS and Android platforms, enabling vector search in mobile nClaw deployments.

Targets to build:
  iOS:
    - aarch64-apple-ios        (Physical devices)
    - aarch64-apple-ios-sim    (Simulator on Apple Silicon)
    - x86_64-apple-ios         (Legacy Intel simulator)

  Android:
    - aarch64-linux-android    (ARM 64-bit)
    - armv7-linux-androideabi  (ARM 32-bit)
    - x86_64-linux-android     (x86 64-bit)
    - i686-linux-android       (x86 32-bit)

Toolchain:
  iOS:      clang from Xcode (command line tools required, run xcode-select --install)
  Android:  Android NDK r26+ (set ANDROID_NDK_HOME env var to NDK root)

Source:
  Clone: https://github.com/asg017/sqlite-vec
  Branch: main (or stable release tag)

Build steps (TBD in S16.T02b):
  1. Download sqlite-vec source
  2. For each iOS target:
     - Run platform-specific build with clang
     - Output: libvec0.a (static archive)
  3. For each Android target:
     - Set ANDROID_NDK_HOME and target triple
     - Run NDK build script
     - Output: libvec0.so (shared object)
  4. Bundle artifacts by platform and CPU architecture

Output structure (target locations):
  nclaw/core/mobile/ios/Frameworks/SqliteVec.xcframework/
    ├── ios-aarch64/
    │   └── libvec0.a
    ├── ios-arm64-simulator/
    │   └── libvec0.a
    └── ios-x86_64-simulator/
        └── libvec0.a

  nclaw/core/mobile/android/app/src/main/jniLibs/
    ├── arm64-v8a/
    │   └── libvec0.so
    ├── armeabi-v7a/
    │   └── libvec0.so
    ├── x86/
    │   └── libvec0.so
    └── x86_64/
        └── libvec0.so

Integration:
  iOS: Link xcframework in Xcode build phases (or via CocoaPods)
  Android: Rust's jni crate will load from jniLibs/<abi>/ at runtime

Timeline:
  S16.T02b (future ticket): Implement full multi-arch build + CI integration
  Until then: manual builds are unsupported (libnclaw feature-gated)

Reference:
  - sqlite-vec docs: https://github.com/asg017/sqlite-vec/blob/main/docs/
  - Rust FFI: std::ffi::CStr for loading extension names
  - Android NDK setup: https://developer.android.com/ndk/downloads
EOF
