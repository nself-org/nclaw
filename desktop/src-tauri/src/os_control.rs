//! T-2165: OS control -- keyboard/mouse simulation via enigo crate.
//! Server sends commands, companion executes native input events.
//! Actions: type_text, key_combo, mouse_click, active_window.
//! All actions require explicit allowlist in config.

use enigo::{Enigo, Keyboard, Mouse, Settings};
use serde::{Deserialize, Serialize};

/// Allowed OS control actions. Must be explicitly listed in config.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum OsAction {
    TypeText,
    KeyCombo,
    MouseClick,
    ActiveWindow,
}

impl OsAction {
    fn from_str(s: &str) -> Option<Self> {
        match s {
            "type_text" => Some(Self::TypeText),
            "key_combo" => Some(Self::KeyCombo),
            "mouse_click" => Some(Self::MouseClick),
            "active_window" => Some(Self::ActiveWindow),
            _ => None,
        }
    }
}

/// Handle an OS control command from the server.
/// Checks the action against the config allowlist before executing.
pub async fn handle_os_command(
    command: &serde_json::Value,
) -> Result<serde_json::Value, String> {
    let action_str = command["action"].as_str().unwrap_or("");
    let action = OsAction::from_str(action_str)
        .ok_or_else(|| format!("unknown os_control action: {action_str}"))?;

    // Check allowlist from config
    let config = crate::config::load_config();
    if !is_action_allowed(&action, &config.allowed_os_actions) {
        tracing::warn!(
            action = %action_str,
            "os_control: action not in allowlist, rejecting"
        );
        return Err(format!(
            "os_control action '{action_str}' is not in the allowed_os_actions config list"
        ));
    }

    match action {
        OsAction::TypeText => {
            let text = command["text"]
                .as_str()
                .ok_or("type_text requires 'text' field")?;
            type_text(text)?;
            Ok(serde_json::json!({"ok": true, "action": "type_text"}))
        }
        OsAction::KeyCombo => {
            let keys = command["keys"]
                .as_array()
                .ok_or("key_combo requires 'keys' array")?;
            let key_strs: Vec<&str> = keys
                .iter()
                .filter_map(|k| k.as_str())
                .collect();
            key_combo(&key_strs)?;
            Ok(serde_json::json!({"ok": true, "action": "key_combo"}))
        }
        OsAction::MouseClick => {
            let x = command["x"]
                .as_f64()
                .ok_or("mouse_click requires 'x' coordinate")? as i32;
            let y = command["y"]
                .as_f64()
                .ok_or("mouse_click requires 'y' coordinate")? as i32;
            let button = command["button"].as_str().unwrap_or("left");
            mouse_click(x, y, button)?;
            Ok(serde_json::json!({"ok": true, "action": "mouse_click", "x": x, "y": y}))
        }
        OsAction::ActiveWindow => {
            let name = get_active_window_name();
            Ok(serde_json::json!({"action": "active_window", "window": name}))
        }
    }
}

/// Check if an action is in the user's allowlist.
fn is_action_allowed(action: &OsAction, allowed: &[String]) -> bool {
    let action_str = match action {
        OsAction::TypeText => "type_text",
        OsAction::KeyCombo => "key_combo",
        OsAction::MouseClick => "mouse_click",
        OsAction::ActiveWindow => "active_window",
    };
    allowed.iter().any(|a| a == action_str || a == "all")
}

/// Type text using native keyboard simulation via enigo.
fn type_text(text: &str) -> Result<(), String> {
    let mut enigo = Enigo::new(&Settings::default())
        .map_err(|e| format!("enigo init failed: {e}"))?;
    enigo
        .text(text)
        .map_err(|e| format!("enigo type_text failed: {e}"))?;
    tracing::info!(chars = text.len(), "os_control: type_text executed");
    Ok(())
}

/// Execute a key combination (e.g., ["cmd", "c"] for Cmd+C).
fn key_combo(keys: &[&str]) -> Result<(), String> {
    let mut enigo = Enigo::new(&Settings::default())
        .map_err(|e| format!("enigo init failed: {e}"))?;

    // Parse key names to enigo Key enum
    let parsed: Vec<enigo::Key> = keys
        .iter()
        .map(|k| parse_key(k))
        .collect::<Result<Vec<_>, _>>()?;

    // Press all modifier keys, then the final key, then release in reverse
    if parsed.is_empty() {
        return Err("key_combo: empty key list".into());
    }

    // All but last are modifiers, last is the main key
    let (modifiers, main_keys) = parsed.split_at(parsed.len().saturating_sub(1));

    for key in modifiers {
        enigo
            .key(*key, enigo::Direction::Press)
            .map_err(|e| format!("key press failed: {e}"))?;
    }

    for key in main_keys {
        enigo
            .key(*key, enigo::Direction::Click)
            .map_err(|e| format!("key click failed: {e}"))?;
    }

    for key in modifiers.iter().rev() {
        enigo
            .key(*key, enigo::Direction::Release)
            .map_err(|e| format!("key release failed: {e}"))?;
    }

    tracing::info!(keys = ?keys, "os_control: key_combo executed");
    Ok(())
}

/// Parse a key name string into an enigo Key.
fn parse_key(name: &str) -> Result<enigo::Key, String> {
    match name.to_lowercase().as_str() {
        // Modifiers
        "cmd" | "command" | "meta" | "super" => Ok(enigo::Key::Meta),
        "ctrl" | "control" => Ok(enigo::Key::Control),
        "alt" | "option" => Ok(enigo::Key::Alt),
        "shift" => Ok(enigo::Key::Shift),

        // Special keys
        "return" | "enter" => Ok(enigo::Key::Return),
        "tab" => Ok(enigo::Key::Tab),
        "space" => Ok(enigo::Key::Space),
        "backspace" | "delete" => Ok(enigo::Key::Backspace),
        "escape" | "esc" => Ok(enigo::Key::Escape),
        "up" => Ok(enigo::Key::UpArrow),
        "down" => Ok(enigo::Key::DownArrow),
        "left" => Ok(enigo::Key::LeftArrow),
        "right" => Ok(enigo::Key::RightArrow),
        "home" => Ok(enigo::Key::Home),
        "end" => Ok(enigo::Key::End),
        "pageup" => Ok(enigo::Key::PageUp),
        "pagedown" => Ok(enigo::Key::PageDown),

        // Function keys
        "f1" => Ok(enigo::Key::F1),
        "f2" => Ok(enigo::Key::F2),
        "f3" => Ok(enigo::Key::F3),
        "f4" => Ok(enigo::Key::F4),
        "f5" => Ok(enigo::Key::F5),
        "f6" => Ok(enigo::Key::F6),
        "f7" => Ok(enigo::Key::F7),
        "f8" => Ok(enigo::Key::F8),
        "f9" => Ok(enigo::Key::F9),
        "f10" => Ok(enigo::Key::F10),
        "f11" => Ok(enigo::Key::F11),
        "f12" => Ok(enigo::Key::F12),

        // Single character keys
        s if s.len() == 1 => Ok(enigo::Key::Unicode(s.chars().next().unwrap())),

        _ => Err(format!("unknown key: {name}")),
    }
}

/// Move mouse to coordinates and click.
fn mouse_click(x: i32, y: i32, button: &str) -> Result<(), String> {
    let mut enigo = Enigo::new(&Settings::default())
        .map_err(|e| format!("enigo init failed: {e}"))?;

    enigo
        .move_mouse(x, y, enigo::Coordinate::Abs)
        .map_err(|e| format!("mouse move failed: {e}"))?;

    let btn = match button {
        "left" => enigo::Button::Left,
        "right" => enigo::Button::Right,
        "middle" => enigo::Button::Middle,
        _ => return Err(format!("unknown mouse button: {button}")),
    };

    enigo
        .button(btn, enigo::Direction::Click)
        .map_err(|e| format!("mouse click failed: {e}"))?;

    tracing::info!(x = x, y = y, button = button, "os_control: mouse_click executed");
    Ok(())
}

/// Get the name of the currently active window (macOS).
#[cfg(target_os = "macos")]
fn get_active_window_name() -> String {
    // Use AppleScript via osascript for reliable active window detection.
    // This avoids pulling in the full Accessibility framework.
    let output = std::process::Command::new("osascript")
        .arg("-e")
        .arg("tell application \"System Events\" to get name of first application process whose frontmost is true")
        .output();

    match output {
        Ok(out) if out.status.success() => {
            String::from_utf8_lossy(&out.stdout).trim().to_string()
        }
        _ => "unknown".into(),
    }
}

#[cfg(not(target_os = "macos"))]
fn get_active_window_name() -> String {
    "unknown (unsupported platform)".into()
}
