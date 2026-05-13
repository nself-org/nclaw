# Mobile FFI Bridge

libnclaw exposes a C-ABI surface so Swift (iOS) and Kotlin/JNI (Android) can
call into the Rust core without async glue. This page documents the bridge:
exports, build steps, and platform damper wiring.

## Rust exports

All C-ABI functions are declared `#[no_mangle] pub extern "C"` in
`core/src/mobile_ffi.rs` and declared in `core/include/libnclaw.h`.

| Function | Signature | Purpose |
|---|---|---|
| `nclaw_set_low_power` | `(flag: bool)` | Notify core that iOS/Android Low Power Mode changed |
| `nclaw_set_battery_pct` | `(pct: u8)` | Send current battery % (0–100); clamps above 100 |
| `nclaw_set_thermal_level` | `(level: u8)` | Send thermal pressure: 0=nominal 1=fair 2=serious 3=critical |

The complete crypto and error-handling surface (`libnclaw_keypair_*`,
`libnclaw_cipher_*`, `libnclaw_last_error`, `libnclaw_version`) is documented
in `core/include/libnclaw.h`.

## Build scripts

### iOS — `.xcframework`

```bash
./scripts/build-ios.sh
# Outputs: mobile/ios/libnclaw.xcframework
```

Requires: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`, Xcode CLI tools.
Bundles both device and Simulator slices so Xcode picks the right one automatically.
Link the framework in Xcode under *General > Frameworks, Libraries, and Embedded Content*.
Add a bridging header that imports `core/include/libnclaw.h`.

### Android — `.so` per ABI

```bash
./scripts/build-android.sh
# Outputs: mobile/android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a}/libnclaw.so
```

Requires: `cargo install cargo-ndk`, Android NDK with `ANDROID_NDK_HOME` set,
`rustup target add aarch64-linux-android armv7-linux-androideabi`.
Gradle picks up the `.so` files automatically — no CMake changes needed.

## Damper wiring

### iOS (`mobile/ios/Runner/AppDelegate.swift`)

`AppDelegate` calls `nclaw_set_low_power()` on launch, on
`applicationDidBecomeActive`, and on `NSProcessInfoPowerStateDidChange`
notifications. This keeps the core tier classifier accurate through
app-lifecycle events and mid-session power-mode toggles.

### Android (`mobile/android/app/src/main/kotlin/com/nself/claw/MainActivity.kt`)

`MainActivity` calls `nclawSetLowPower` (JNI bridge to `nclaw_set_low_power`)
via a `PowerManager.ACTION_POWER_SAVE_MODE_CHANGED` broadcast receiver, and
`nclawSetBatteryPct` (JNI bridge to `nclaw_set_battery_pct`) via an
`ACTION_BATTERY_CHANGED` sticky intent receiver. Both sync on `onResume`.

## Damper logic (`core/src/llm/dampers.rs`)

Three pure functions, fully unit-tested:

- `apply_low_power_damper(tier, low_power)` — drops tier by one when low power is on; T0 is the floor.
- `local_llm_disabled_by_battery(state)` — returns true when not charging and battery is below the threshold (default 30 %).
- `thermal_inter_token_delay_ms(level)` — returns 0 ms (nominal/fair), 50 ms (serious), or 200 ms (critical).

Run the damper tests:

```bash
cd core && cargo test llm::dampers
```
