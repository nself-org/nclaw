package com.nself.claw

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity

// S15-T18: Mobile FFI damper wiring.
//
// Notifies the Rust libnclaw core of Android Low Power Mode and battery state
// changes via JNI calls to the C-ABI exports in libnclaw.so:
//   - nclaw_set_low_power(flag: Boolean)
//   - nclaw_set_battery_pct(pct: Byte)
//
// libnclaw.so is placed by build-android.sh into
//   app/src/main/jniLibs/{arm64-v8a,armeabi-v7a}/libnclaw.so
// and loaded below via System.loadLibrary.

class MainActivity : FlutterActivity() {

    private var powerSaveReceiver: BroadcastReceiver? = null
    private var batteryReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Load the Rust FFI library. The .so is bundled into the APK via
        // jniLibs; System.loadLibrary resolves the correct ABI slice at runtime.
        System.loadLibrary("nclaw")

        // Send initial power-save state before registering the receiver.
        syncPowerSaveMode()
        syncBatteryLevel()

        // Register a receiver for Power Save Mode toggle events. This intent
        // fires on the main thread when the user enables/disables Battery Saver.
        powerSaveReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == PowerManager.ACTION_POWER_SAVE_MODE_CHANGED) {
                    syncPowerSaveMode()
                }
            }
        }
        registerReceiver(
            powerSaveReceiver,
            IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
        )

        // Register a receiver for battery level changes. ACTION_BATTERY_CHANGED
        // is a sticky intent — registering with a null receiver returns the
        // last-known state immediately, so syncBatteryLevel() above already has
        // the correct value. The receiver here catches subsequent changes.
        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == Intent.ACTION_BATTERY_CHANGED) {
                    val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                    val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
                    if (level >= 0 && scale > 0) {
                        val pct = ((level.toFloat() / scale.toFloat()) * 100f).toInt()
                            .coerceIn(0, 100)
                            .toByte()
                        nclawSetBatteryPct(pct)
                    }
                }
            }
        }
        registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    }

    override fun onResume() {
        super.onResume()
        // Re-sync on foreground: state may have changed while the app was paused.
        syncPowerSaveMode()
        syncBatteryLevel()
    }

    override fun onDestroy() {
        powerSaveReceiver?.let { unregisterReceiver(it) }
        batteryReceiver?.let { unregisterReceiver(it) }
        super.onDestroy()
    }

    // -------------------------------------------------------------------------
    // Power-save helpers
    // -------------------------------------------------------------------------

    private fun syncPowerSaveMode() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val isLow = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            pm.isPowerSaveMode
        } else {
            false
        }
        nclawSetLowPower(isLow)
    }

    private fun syncBatteryLevel() {
        // Sticky intent — passing null BroadcastReceiver returns last-known intent.
        val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        if (level >= 0 && scale > 0) {
            val pct = ((level.toFloat() / scale.toFloat()) * 100f).toInt()
                .coerceIn(0, 100)
                .toByte()
            nclawSetBatteryPct(pct)
        }
    }

    // -------------------------------------------------------------------------
    // JNI declarations — implemented in core/src/mobile_ffi.rs, compiled into
    // libnclaw.so. Names follow JNI mangling: Java_{package}_{class}_{method}.
    // The C-ABI exports (nclaw_set_low_power etc.) are called via these bridges.
    // -------------------------------------------------------------------------

    private external fun nclawSetLowPower(flag: Boolean)
    private external fun nclawSetBatteryPct(pct: Byte)
}
