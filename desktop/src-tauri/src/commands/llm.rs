// ɳClaw Desktop — LLM commands (Tauri 2 invoke handlers)
//
// Covers:
//   T01 — HuggingFace GGUF search
//   T02 — Resumable download queue management
//   T05 — VRAM / memory telemetry
//   T06 — Hot model swap

use libnclaw::llm::downloader::{DownloadEntry, DownloadProgress, Downloader};
use libnclaw::llm::hf_search::{search_hf, HfModel, HfSearchParams};
use libnclaw::llm::telemetry::{poll_memory, MemorySnapshot};
use std::sync::{Arc, OnceLock};
use tauri::Emitter;
use tokio::sync::Mutex;

// ---------------------------------------------------------------------------
// Global downloader instance
// ---------------------------------------------------------------------------

fn downloader() -> &'static Arc<Mutex<Downloader>> {
    static DL: OnceLock<Arc<Mutex<Downloader>>> = OnceLock::new();
    DL.get_or_init(|| {
        let models_dir = dirs::data_local_dir()
            .unwrap_or_else(std::env::temp_dir)
            .join("nclaw")
            .join("models");
        Arc::new(Mutex::new(Downloader::new(models_dir)))
    })
}

// ---------------------------------------------------------------------------
// Models directory helper
// ---------------------------------------------------------------------------

/// Return the absolute path to the local models directory.
///
/// Used by the frontend to construct the full file path after a download
/// completes so it can pass an absolute path to `llm_swap_model`.
#[tauri::command]
pub async fn llm_get_models_dir() -> Result<String, String> {
    let path = dirs::data_local_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join("nclaw")
        .join("models");
    std::fs::create_dir_all(&path)
        .map_err(|e| format!("create models dir: {e}"))?;
    path.to_str()
        .map(|s| s.to_owned())
        .ok_or_else(|| "models dir path is not valid UTF-8".to_owned())
}

// ---------------------------------------------------------------------------
// T01 — HuggingFace search
// ---------------------------------------------------------------------------

/// Search HuggingFace for GGUF models.
///
/// Results are cached for 5 minutes on the Rust side.
#[tauri::command]
pub async fn llm_search_hf(query: String, limit: Option<u32>) -> Result<Vec<HfModel>, String> {
    search_hf(HfSearchParams {
        query,
        limit: limit.unwrap_or(20),
    })
    .await
}

// ---------------------------------------------------------------------------
// T02 — Download queue
// ---------------------------------------------------------------------------

/// Add a model download to the queue. Returns the new download ID.
#[tauri::command]
pub async fn llm_download_start(
    app: tauri::AppHandle,
    url: String,
    filename: String,
    expected_sha256: Option<String>,
) -> Result<String, String> {
    let dl = downloader().lock().await;

    // Subscribe to progress before starting so we don't miss early events.
    let mut progress_rx = dl.subscribe_progress();

    let id = dl.enqueue(url, filename, expected_sha256).await;
    dl.start_download(&id).await?;

    // Forward progress events to the frontend via Tauri emit.
    let id_clone = id.clone();
    let app_clone = app.clone();
    tokio::spawn(async move {
        while let Ok(progress) = progress_rx.recv().await {
            if progress.id == id_clone {
                let done = matches!(
                    progress.status,
                    libnclaw::llm::downloader::DownloadStatus::Done
                        | libnclaw::llm::downloader::DownloadStatus::Failed(_)
                        | libnclaw::llm::downloader::DownloadStatus::Cancelled
                );
                let _ = app_clone.emit("llm://download-progress", &progress);
                if done {
                    break;
                }
            }
        }
    });

    Ok(id)
}

/// Cancel an in-progress or queued download.
#[tauri::command]
pub async fn llm_download_cancel(id: String) -> Result<(), String> {
    downloader().lock().await.cancel(&id).await;
    Ok(())
}

/// Return the current download queue snapshot.
#[tauri::command]
pub async fn llm_download_list() -> Result<Vec<DownloadEntry>, String> {
    Ok(downloader().lock().await.list().await)
}

// ---------------------------------------------------------------------------
// T05 — Memory / VRAM telemetry
// ---------------------------------------------------------------------------

// Whether the telemetry polling task is running.
static TELEMETRY_RUNNING: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

/// Start emitting `llm://memory-snapshot` events to the frontend every second.
///
/// Idempotent — calling multiple times has no effect if already running.
#[tauri::command]
pub async fn llm_telemetry_start(app: tauri::AppHandle) {
    if TELEMETRY_RUNNING.swap(true, std::sync::atomic::Ordering::Relaxed) {
        return; // already running
    }
    tokio::spawn(async move {
        loop {
            if !TELEMETRY_RUNNING.load(std::sync::atomic::Ordering::Relaxed) {
                break;
            }
            let snap = poll_memory();
            let _ = app.emit("llm://memory-snapshot", &snap);
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        }
    });
}

/// Stop the telemetry polling task.
#[tauri::command]
pub async fn llm_telemetry_stop() {
    TELEMETRY_RUNNING.store(false, std::sync::atomic::Ordering::Relaxed);
}

/// Return a single on-demand memory snapshot (no subscription needed).
#[tauri::command]
pub async fn llm_memory_snapshot() -> Result<MemorySnapshot, String> {
    Ok(poll_memory())
}

// ---------------------------------------------------------------------------
// T06 — Hot model swap
// ---------------------------------------------------------------------------

/// Hot-swap the loaded llama.cpp model to a new GGUF file.
///
/// Unloads the current model (freeing VRAM), then loads the new one.
/// The `path` must be an absolute path to a `.gguf` file on the local
/// filesystem.
///
/// Tauri events emitted:
///   - `llm://swap-start`  — swap initiated (payload: path string)
///   - `llm://swap-done`   — swap complete (payload: model filename)
///   - `llm://swap-error`  — swap failed (payload: error string)
#[cfg(any(
    feature = "cpu",
    feature = "metal",
    feature = "cuda",
    feature = "vulkan"
))]
#[tauri::command]
pub async fn llm_swap_model(app: tauri::AppHandle, path: String) -> Result<(), String> {
    use libnclaw::llm::backend::llamacpp::LlamaCpp;
    use std::path::PathBuf;

    let gguf_path = PathBuf::from(&path);
    if !gguf_path.exists() {
        return Err(format!("model file not found: {path}"));
    }
    if gguf_path.extension().and_then(|e| e.to_str()) != Some("gguf") {
        return Err(format!("not a .gguf file: {path}"));
    }

    let _ = app.emit("llm://swap-start", &path);

    let instance = global_llamacpp();
    let mut guard = instance.lock().await;

    match guard.as_mut() {
        None => {
            let mut backend =
                LlamaCpp::new().map_err(|e| format!("llama.cpp init: {e}"))?;
            backend.load_model(&gguf_path).map_err(|e| {
                let msg = format!("load_model: {e}");
                let _ = app.emit("llm://swap-error", &msg);
                msg
            })?;
            *guard = Some(backend);
        }
        Some(backend) => {
            // Take + drop the model before loading the next — zero VRAM overlap.
            backend.unload_model();
            backend.load_model(&gguf_path).map_err(|e| {
                let msg = format!("load_model: {e}");
                let _ = app.emit("llm://swap-error", &msg);
                msg
            })?;
        }
    }

    let model_name = gguf_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_owned();
    let _ = app.emit("llm://swap-done", &model_name);
    Ok(())
}

/// Stub when no llama.cpp feature is compiled in.
#[cfg(not(any(
    feature = "cpu",
    feature = "metal",
    feature = "cuda",
    feature = "vulkan"
)))]
#[tauri::command]
pub async fn llm_swap_model(_app: tauri::AppHandle, _path: String) -> Result<(), String> {
    Err("llama.cpp not compiled in — enable cpu | metal | cuda | vulkan feature".into())
}

// ---------------------------------------------------------------------------
// Global LlamaCpp instance (feature-gated)
// ---------------------------------------------------------------------------

#[cfg(any(
    feature = "cpu",
    feature = "metal",
    feature = "cuda",
    feature = "vulkan"
))]
fn global_llamacpp() -> &'static Arc<Mutex<Option<libnclaw::llm::backend::llamacpp::LlamaCpp>>> {
    static INSTANCE: OnceLock<
        Arc<Mutex<Option<libnclaw::llm::backend::llamacpp::LlamaCpp>>>,
    > = OnceLock::new();
    INSTANCE.get_or_init(|| Arc::new(Mutex::new(None)))
}
