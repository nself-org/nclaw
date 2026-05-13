#!/usr/bin/env bash
set -euo pipefail

# flutter_rust_bridge codegen pipeline for nClaw mobile
# Generates Dart FFI bindings from nclaw/core/src/api.rs

cd "$(dirname "$0")/.."

# Ensure Flutter dependencies are installed
flutter pub get

# Run the codegen
dart run flutter_rust_bridge_codegen generate

# Verify output directory exists
if [ -d "lib/src/rust" ]; then
  echo "✓ Bindings regenerated at lib/src/rust/"
  ls -la lib/src/rust/ | head -10
else
  echo "⚠ Warning: lib/src/rust/ directory not found after codegen"
fi
