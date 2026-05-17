// ɳClaw Desktop — Backend Tauri commands (S17 Embedded-PG path)
//
// Exposes a `start_embedded_pg` command the frontend can call to ask the
// locally-installed nSelf CLI to boot its embedded-PG stack
// (`nself start --embedded-pg`). The command runs the CLI as a subprocess,
// streams stderr/stdout to the Tauri app event bus, and returns a typed
// result the frontend can bind against a `backendStore` reactive slice.
//
// Why a subprocess instead of embedding the CLI logic?
//   - The CLI binary owns the Docker-Compose orchestration, WASM fetch,
//     wasmtime module compilation, and AF_UNIX socket bridge. Reimplementing
//     that surface inside the Tauri process violates the CLI-first hard rule
//     (nSelf PPI §CLI-First).
//   - The CLI already exposes `nself start --embedded-pg`. We call it.

use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use tauri::{AppHandle, Emitter};

// ---- Types ------------------------------------------------------------------

/// Outcome returned to the frontend after attempting to start the embedded-PG
/// stack. The frontend binds this to `backendStore.embeddedPgResult`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EmbeddedPgResult {
    /// true when the CLI exited 0 (stack booted).
    pub ok: bool,
    /// CLI exit code (0 = success).
    pub exit_code: i32,
    /// Human-readable message. Non-empty on failure.
    pub message: String,
}

// ---- Command ----------------------------------------------------------------

/// Start the ɳSelf embedded-PG backend via the nSelf CLI.
///
/// Behaviour:
/// 1. Locate the `nself` binary (PATH first, then common install locations).
/// 2. Spawn `nself start --embedded-pg` as a subprocess.
/// 3. Stream each stdout/stderr line back to the frontend via the Tauri event
///    `backend://log` so the UI can show a live progress feed.
/// 4. Wait for the process to exit and return an `EmbeddedPgResult`.
///
/// The command is `async` so Tauri dispatches it on the async thread pool and
/// the frontend can `await invoke(...)` without blocking the main thread.
#[tauri::command]
pub async fn start_embedded_pg(app: AppHandle) -> Result<EmbeddedPgResult, String> {
    let nself_bin = locate_nself_binary()?;

    let mut child = Command::new(&nself_bin)
        .args(["start", "--embedded-pg"])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("failed to spawn '{}': {}", nself_bin, e))?;

    // Stream stdout to frontend events.
    if let Some(stdout) = child.stdout.take() {
        let app_out = app.clone();
        let reader = BufReader::new(stdout);
        for line in reader.lines() {
            match line {
                Ok(l) => {
                    let _ = app_out.emit("backend://log", &l);
                }
                Err(e) => {
                    let _ = app_out.emit("backend://log", &format!("[stdout read error] {}", e));
                    break;
                }
            }
        }
    }

    // Stream stderr to frontend events.
    if let Some(stderr) = child.stderr.take() {
        let app_err = app.clone();
        let reader = BufReader::new(stderr);
        for line in reader.lines() {
            match line {
                Ok(l) => {
                    let _ = app_err.emit("backend://log", &format!("[stderr] {}", l));
                }
                Err(e) => {
                    let _ = app_err.emit("backend://log", &format!("[stderr read error] {}", e));
                    break;
                }
            }
        }
    }

    let status = child
        .wait()
        .map_err(|e| format!("failed to wait for nself process: {}", e))?;

    let exit_code = status.code().unwrap_or(-1);
    let ok = exit_code == 0;
    let message = if ok {
        String::new()
    } else {
        format!(
            "nself start --embedded-pg exited with code {}; check 'backend://log' events for details",
            exit_code
        )
    };

    Ok(EmbeddedPgResult {
        ok,
        exit_code,
        message,
    })
}

// ---- Helpers ----------------------------------------------------------------

/// Locate the `nself` CLI binary.
///
/// Search order:
/// 1. PATH (standard; covers Homebrew and manual installs)
/// 2. `/usr/local/bin/nself` (common Homebrew prefix on Intel macOS)
/// 3. `/opt/homebrew/bin/nself` (Apple Silicon Homebrew)
/// 4. `~/.nself/bin/nself` (manual install fallback)
fn locate_nself_binary() -> Result<String, String> {
    // 1. PATH via `which` / shell resolution — try `nself --version` quickly.
    if let Ok(out) = Command::new("nself").arg("--version").output() {
        if out.status.success() {
            return Ok("nself".to_string());
        }
    }

    // 2-4. Absolute fallbacks.
    let candidates = [
        "/usr/local/bin/nself",
        "/opt/homebrew/bin/nself",
        "~/.nself/bin/nself",
    ];
    for candidate in &candidates {
        let expanded = if candidate.starts_with('~') {
            if let Ok(home) = std::env::var("HOME") {
                candidate.replacen('~', &home, 1)
            } else {
                continue;
            }
        } else {
            candidate.to_string()
        };
        if std::path::Path::new(&expanded).exists() {
            return Ok(expanded);
        }
    }

    Err(
        "nself CLI not found — install via Homebrew: `brew install nself-org/tap/nself`"
            .to_string(),
    )
}
