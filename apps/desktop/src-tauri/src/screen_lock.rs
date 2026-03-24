//! T-2164: Screen lock detection.
//! Detects macOS screen lock via CoreGraphics CGSessionCopyCurrentDictionary.
//! Reports state changes to the server via WS.

use tauri::Manager;
use std::sync::atomic::{AtomicBool, Ordering};

static SCREEN_LOCKED: AtomicBool = AtomicBool::new(false);

/// Check if the screen is currently locked (macOS).
/// Uses CGSessionCopyCurrentDictionary to read the session dictionary.
#[cfg(target_os = "macos")]
pub fn is_screen_locked() -> bool {
    unsafe {
        // CGSessionCopyCurrentDictionary returns a CFDictionary.
        // The key "CGSSessionScreenIsLocked" is set to 1 when locked.
        let session_dict = CGSessionCopyCurrentDictionary();
        if session_dict.is_null() {
            return false;
        }

        let key = cfstring("CGSSessionScreenIsLocked");
        let mut value: i32 = 0;
        let found = CFDictionaryGetValueIfPresent(
            session_dict,
            key as *const _,
            &mut value as *mut i32 as *mut *const std::ffi::c_void,
        );
        CFRelease(session_dict as *const _);
        CFRelease(key as *const _);

        // If the key exists, check if the value is truthy.
        // CFDictionaryGetValueIfPresent sets the value pointer to the CFBoolean.
        // For a CFBoolean kCFBooleanTrue, the pointer value is non-zero.
        found != 0 && value != 0
    }
}

#[cfg(not(target_os = "macos"))]
pub fn is_screen_locked() -> bool {
    false
}

/// Watch for screen lock/unlock events and notify the server via WS.
///
/// On macOS, uses CFNotificationCenter to listen for:
/// - com.apple.screenIsLocked
/// - com.apple.screenIsUnlocked
///
/// Sends state changes through the WS connection.
#[cfg(target_os = "macos")]
pub async fn watch_screen_lock(app_handle: tauri::AppHandle) {
    tracing::info!("Screen lock watcher started (macOS)");

    // Set initial state
    SCREEN_LOCKED.store(is_screen_locked(), Ordering::SeqCst);

    // We use a polling approach with CGSessionCopyCurrentDictionary because
    // subscribing to NSDistributedNotificationCenter from a Rust async context
    // requires running an NSRunLoop, which conflicts with tokio. Polling every
    // 5 seconds is a reliable cross-runtime approach.
    let mut previous_state = SCREEN_LOCKED.load(Ordering::SeqCst);

    loop {
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;

        let current = is_screen_locked();
        SCREEN_LOCKED.store(current, Ordering::SeqCst);

        if current != previous_state {
            tracing::info!(
                locked = current,
                "Screen lock state changed"
            );

            // Send state change through WS if sender is available
            if let Some(state) = app_handle.try_state::<crate::ws_client::WsSenderState>() {
                let msg = serde_json::json!({
                    "type": "screen_lock_changed",
                    "locked": current,
                    "timestamp": chrono_timestamp(),
                });
                let _ = state.0.send(msg.to_string());
            }

            previous_state = current;
        }
    }
}

#[cfg(not(target_os = "macos"))]
pub async fn watch_screen_lock(_app_handle: tauri::AppHandle) {
    tracing::info!("Screen lock watcher not available on this platform");
}

/// Get a simple ISO-8601 timestamp without pulling in chrono.
fn chrono_timestamp() -> String {
    // Use std::time for a Unix timestamp. Full ISO formatting would need chrono,
    // but for a simple WS message, epoch seconds suffice.
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs().to_string())
        .unwrap_or_else(|_| "0".into())
}

// --- macOS CoreGraphics FFI bindings ---

#[cfg(target_os = "macos")]
extern "C" {
    fn CGSessionCopyCurrentDictionary() -> *const std::ffi::c_void;
    fn CFDictionaryGetValueIfPresent(
        dict: *const std::ffi::c_void,
        key: *const std::ffi::c_void,
        value: *mut *const std::ffi::c_void,
    ) -> u8;
    fn CFRelease(cf: *const std::ffi::c_void);
    fn CFStringCreateWithBytes(
        alloc: *const std::ffi::c_void,
        bytes: *const u8,
        num_bytes: isize,
        encoding: u32,
        is_external: u8,
    ) -> *const std::ffi::c_void;
}

#[cfg(target_os = "macos")]
const K_CF_STRING_ENCODING_UTF8: u32 = 0x08000100;

/// Create a CFString from a Rust string slice.
#[cfg(target_os = "macos")]
unsafe fn cfstring(s: &str) -> *const std::ffi::c_void {
    CFStringCreateWithBytes(
        std::ptr::null(),
        s.as_ptr(),
        s.len() as isize,
        K_CF_STRING_ENCODING_UTF8,
        0,
    )
}
