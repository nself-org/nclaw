//! Resumable GGUF model downloader with SHA256 verification and SQLite queue persistence.
//!
//! # Architecture
//!
//! Downloads proceed as follows:
//! 1. Caller enqueues a download via [`enqueue`], receiving a unique `download_id`.
//! 2. Caller calls [`start_download`] which spawns a Tokio task.
//! 3. The task uses HTTP Range requests to resume partial downloads stored as `<hash>.part`.
//! 4. On completion the file is SHA256-verified, then renamed to `<filename>`.
//! 5. Progress is broadcast over a [`tokio::sync::broadcast`] channel at ~1Hz.
//! 6. The SQLite queue (`downloads.db`) persists state across restarts.
//!
//! The `mobile-sqlite` feature flag gates rusqlite. When the feature is absent the
//! SQLite helpers are compiled out and queue persistence is in-memory only.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::{broadcast, Mutex, RwLock};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Status of a single download entry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DownloadStatus {
    Queued,
    Downloading,
    Verifying,
    Done,
    Failed(String),
    Cancelled,
}

/// A download queue entry.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadEntry {
    /// Unique identifier assigned by [`enqueue`].
    pub id: String,
    /// Remote URL to download from.
    pub url: String,
    /// Target filename (not full path — the downloader appends to the models dir).
    pub filename: String,
    /// Expected SHA256 hex digest for integrity verification (`None` = skip verify).
    pub expected_sha256: Option<String>,
    /// Current download status.
    pub status: DownloadStatus,
    /// Bytes received so far.
    pub bytes_received: u64,
    /// Total content length (`None` when server does not report it).
    pub total_bytes: Option<u64>,
}

/// Progress snapshot emitted on the broadcast channel.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadProgress {
    pub id: String,
    pub status: DownloadStatus,
    pub bytes_received: u64,
    pub total_bytes: Option<u64>,
    /// Download speed in bytes/sec (rolling 1-second window).
    pub bytes_per_sec: u64,
}

// ---------------------------------------------------------------------------
// Downloader state
// ---------------------------------------------------------------------------

/// Capacity of the broadcast progress channel.
const PROGRESS_CHAN_CAP: usize = 64;

/// In-memory queue entry with channel sender.
struct ActiveDownload {
    entry: DownloadEntry,
    /// Cancel signal: set to `true` to abort the running task.
    cancel: Arc<std::sync::atomic::AtomicBool>,
}

/// Central downloader state — wrap in `Arc<Mutex<>>` for shared access.
pub struct Downloader {
    /// Directory where completed models are stored.
    models_dir: PathBuf,
    /// In-flight and queued downloads.
    queue: Arc<RwLock<Vec<ActiveDownload>>>,
    /// Progress broadcast sender — receivers can subscribe any time.
    progress_tx: broadcast::Sender<DownloadProgress>,
}

impl Downloader {
    /// Create a new downloader targeting `models_dir`.
    ///
    /// The directory is created if it does not exist.
    pub fn new(models_dir: impl Into<PathBuf>) -> Self {
        let (tx, _) = broadcast::channel(PROGRESS_CHAN_CAP);
        let dir: PathBuf = models_dir.into();
        // Best-effort directory creation; callers should verify before using.
        let _ = std::fs::create_dir_all(&dir);
        Self {
            models_dir: dir,
            queue: Arc::new(RwLock::new(Vec::new())),
            progress_tx: tx,
        }
    }

    /// Subscribe to progress events for all downloads.
    pub fn subscribe_progress(&self) -> broadcast::Receiver<DownloadProgress> {
        self.progress_tx.subscribe()
    }

    /// Enqueue a new download, returning the generated download ID.
    pub async fn enqueue(
        &self,
        url: String,
        filename: String,
        expected_sha256: Option<String>,
    ) -> String {
        let id = Uuid::new_v4().to_string();
        let entry = DownloadEntry {
            id: id.clone(),
            url,
            filename,
            expected_sha256,
            status: DownloadStatus::Queued,
            bytes_received: 0,
            total_bytes: None,
        };
        self.queue.write().await.push(ActiveDownload {
            entry,
            cancel: Arc::new(std::sync::atomic::AtomicBool::new(false)),
        });
        id
    }

    /// Return a snapshot of all queue entries.
    pub async fn list(&self) -> Vec<DownloadEntry> {
        self.queue.read().await.iter().map(|a| a.entry.clone()).collect()
    }

    /// Cancel a queued or in-progress download.
    pub async fn cancel(&self, id: &str) {
        let mut guard = self.queue.write().await;
        if let Some(active) = guard.iter_mut().find(|a| a.entry.id == id) {
            active.cancel.store(true, std::sync::atomic::Ordering::Relaxed);
            active.entry.status = DownloadStatus::Cancelled;
        }
    }

    /// Start downloading the entry with the given `id`.
    ///
    /// Spawns a background Tokio task. Progress is broadcast via the channel
    /// returned by [`Downloader::subscribe_progress`].
    ///
    /// Returns `Err` when no entry with `id` exists in the queue.
    pub async fn start_download(&self, id: &str) -> Result<(), String> {
        let (entry, cancel) = {
            let guard = self.queue.read().await;
            let active = guard
                .iter()
                .find(|a| a.entry.id == id)
                .ok_or_else(|| format!("no download with id={id}"))?;
            if active.entry.status != DownloadStatus::Queued {
                return Err(format!("download {id} is not in Queued state"));
            }
            (active.entry.clone(), active.cancel.clone())
        };

        // Mark as Downloading.
        self.update_status(id, DownloadStatus::Downloading).await;

        let queue = self.queue.clone();
        let tx = self.progress_tx.clone();
        let models_dir = self.models_dir.clone();
        let id_owned = id.to_owned();

        tokio::spawn(async move {
            let result =
                download_file(entry.clone(), &models_dir, cancel.clone(), tx.clone()).await;

            // Update final status.
            let final_status = match result {
                Ok(_) => DownloadStatus::Done,
                Err(ref e) => {
                    if cancel.load(std::sync::atomic::Ordering::Relaxed) {
                        DownloadStatus::Cancelled
                    } else {
                        DownloadStatus::Failed(e.clone())
                    }
                }
            };

            let mut guard = queue.write().await;
            if let Some(active) = guard.iter_mut().find(|a| a.entry.id == id_owned) {
                active.entry.status = final_status.clone();
                let _ = tx.send(DownloadProgress {
                    id: id_owned.clone(),
                    status: final_status,
                    bytes_received: active.entry.bytes_received,
                    total_bytes: active.entry.total_bytes,
                    bytes_per_sec: 0,
                });
            }
        });

        Ok(())
    }

    async fn update_status(&self, id: &str, status: DownloadStatus) {
        let mut guard = self.queue.write().await;
        if let Some(active) = guard.iter_mut().find(|a| a.entry.id == id) {
            active.entry.status = status;
        }
    }
}

// ---------------------------------------------------------------------------
// Download task
// ---------------------------------------------------------------------------

/// Perform the actual HTTP download with Range-request resume support.
///
/// On success the completed file is at `<models_dir>/<filename>`.
async fn download_file(
    entry: DownloadEntry,
    models_dir: &Path,
    cancel: Arc<std::sync::atomic::AtomicBool>,
    tx: broadcast::Sender<DownloadProgress>,
) -> Result<(), String> {
    let dest_path = models_dir.join(&entry.filename);
    let part_path = models_dir.join(format!("{}.part", entry.filename));

    // Determine resume offset from existing .part file.
    let resume_from = if part_path.exists() {
        std::fs::metadata(&part_path).map(|m| m.len()).unwrap_or(0)
    } else {
        0
    };

    let client = reqwest::Client::builder()
        .user_agent("nclaw-desktop/1.1.1")
        .build()
        .map_err(|e| format!("http client: {e}"))?;

    let mut req = client.get(&entry.url);
    if resume_from > 0 {
        req = req.header("Range", format!("bytes={}-", resume_from));
    }

    let resp = req.send().await.map_err(|e| format!("request: {e}"))?;

    if !resp.status().is_success() && resp.status().as_u16() != 206 {
        return Err(format!("HTTP {}", resp.status()));
    }

    let total_bytes = resp.content_length().map(|cl| cl + resume_from);

    // Open part file for appending.
    let mut file = tokio::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&part_path)
        .await
        .map_err(|e| format!("open part file: {e}"))?;

    let mut hasher = Sha256::new();
    // If resuming, hash the bytes already downloaded.
    if resume_from > 0 {
        let existing = tokio::fs::read(&part_path)
            .await
            .map_err(|e| format!("re-read part: {e}"))?;
        hasher.update(&existing[..resume_from as usize]);
    }

    let mut received = resume_from;
    let mut last_progress_at = std::time::Instant::now();
    let mut bytes_since_last = 0u64;
    let mut stream = resp.bytes_stream();

    use futures::StreamExt as _;
    use tokio::io::AsyncWriteExt as _;

    while let Some(chunk_result) = stream.next().await {
        if cancel.load(std::sync::atomic::Ordering::Relaxed) {
            return Err("cancelled".into());
        }
        let chunk = chunk_result.map_err(|e| format!("stream chunk: {e}"))?;
        hasher.update(&chunk);
        file.write_all(&chunk).await.map_err(|e| format!("write: {e}"))?;
        received += chunk.len() as u64;
        bytes_since_last += chunk.len() as u64;

        // Emit progress at most once per second.
        let elapsed = last_progress_at.elapsed();
        if elapsed >= std::time::Duration::from_secs(1) {
            let bps = (bytes_since_last as f64 / elapsed.as_secs_f64()) as u64;
            let _ = tx.send(DownloadProgress {
                id: entry.id.clone(),
                status: DownloadStatus::Downloading,
                bytes_received: received,
                total_bytes,
                bytes_per_sec: bps,
            });
            last_progress_at = std::time::Instant::now();
            bytes_since_last = 0;
        }
    }

    file.flush().await.map_err(|e| format!("flush: {e}"))?;
    drop(file);

    // Verify SHA256 if expected hash was provided.
    if let Some(expected) = &entry.expected_sha256 {
        let _ = tx.send(DownloadProgress {
            id: entry.id.clone(),
            status: DownloadStatus::Verifying,
            bytes_received: received,
            total_bytes,
            bytes_per_sec: 0,
        });
        let actual = format!("{:x}", hasher.finalize());
        if actual != *expected {
            return Err(format!(
                "SHA256 mismatch: expected={expected}, got={actual}"
            ));
        }
    }

    // Atomically rename .part → final destination.
    tokio::fs::rename(&part_path, &dest_path)
        .await
        .map_err(|e| format!("rename: {e}"))?;

    Ok(())
}

// ---------------------------------------------------------------------------
// SQLite persistence helpers (feature = "mobile-sqlite")
// ---------------------------------------------------------------------------

/// Persist the current queue to SQLite so it survives process restarts.
///
/// The table schema is created on first call.
#[cfg(feature = "mobile-sqlite")]
pub fn persist_queue(db_path: &Path, entries: &[DownloadEntry]) -> Result<(), String> {
    use rusqlite::Connection;
    let conn = Connection::open(db_path).map_err(|e| e.to_string())?;
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS download_queue (
            id TEXT PRIMARY KEY,
            url TEXT NOT NULL,
            filename TEXT NOT NULL,
            expected_sha256 TEXT,
            status TEXT NOT NULL,
            bytes_received INTEGER NOT NULL DEFAULT 0,
            total_bytes INTEGER
         );",
    )
    .map_err(|e| e.to_string())?;

    for entry in entries {
        conn.execute(
            "INSERT OR REPLACE INTO download_queue
             (id, url, filename, expected_sha256, status, bytes_received, total_bytes)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            rusqlite::params![
                entry.id,
                entry.url,
                entry.filename,
                entry.expected_sha256,
                serde_json::to_string(&entry.status).unwrap_or_default(),
                entry.bytes_received as i64,
                entry.total_bytes.map(|b| b as i64),
            ],
        )
        .map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// Load a persisted queue from SQLite.
#[cfg(feature = "mobile-sqlite")]
pub fn load_queue(db_path: &Path) -> Result<Vec<DownloadEntry>, String> {
    use rusqlite::Connection;
    if !db_path.exists() {
        return Ok(Vec::new());
    }
    let conn = Connection::open(db_path).map_err(|e| e.to_string())?;
    let mut stmt = conn
        .prepare(
            "SELECT id, url, filename, expected_sha256, status, bytes_received, total_bytes
             FROM download_queue",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, Option<String>>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, i64>(5)?,
                row.get::<_, Option<i64>>(6)?,
            ))
        })
        .map_err(|e| e.to_string())?;

    let mut entries = Vec::new();
    for row in rows {
        let (id, url, filename, expected_sha256, status_raw, bytes_received, total_bytes) =
            row.map_err(|e| e.to_string())?;
        let status: DownloadStatus =
            serde_json::from_str(&status_raw).unwrap_or(DownloadStatus::Queued);
        entries.push(DownloadEntry {
            id,
            url,
            filename,
            expected_sha256,
            status,
            bytes_received: bytes_received as u64,
            total_bytes: total_bytes.map(|b| b as u64),
        });
    }
    Ok(entries)
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn enqueue_and_list() {
        let dl = Downloader::new(std::env::temp_dir().join("nclaw-dl-test"));
        let id = dl
            .enqueue(
                "https://example.com/model.gguf".into(),
                "model.gguf".into(),
                None,
            )
            .await;
        let list = dl.list().await;
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].id, id);
        assert_eq!(list[0].status, DownloadStatus::Queued);
    }

    #[tokio::test]
    async fn cancel_changes_status() {
        let dl = Downloader::new(std::env::temp_dir().join("nclaw-dl-cancel-test"));
        let id = dl
            .enqueue("https://example.com/model.gguf".into(), "m.gguf".into(), None)
            .await;
        dl.cancel(&id).await;
        let list = dl.list().await;
        assert_eq!(list[0].status, DownloadStatus::Cancelled);
    }

    #[test]
    fn download_status_serde_roundtrip() {
        let s = DownloadStatus::Failed("test error".into());
        let json = serde_json::to_string(&s).unwrap();
        let back: DownloadStatus = serde_json::from_str(&json).unwrap();
        assert_eq!(s, back);
    }
}
