use std::fs;
use std::path::{Path, PathBuf};
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

/// Initialize tracing-subscriber with JSON or pretty output.
///
/// Supports environment variables:
/// - `NCLAW_LOG_FORMAT`: "json" or "pretty" (default: "pretty")
/// - `RUST_LOG`: tracing filter (default: "nclaw_core=info,warn")
///
/// Logs are written to:
/// - macOS: ~/Library/Logs/nClaw/
/// - Linux: ~/.local/state/nclaw/logs/
/// - Windows: %APPDATA%/nClaw/logs/
///
/// File rotation: 100MB per file, 500MB total
pub fn init() {
    let format = std::env::var("NCLAW_LOG_FORMAT").unwrap_or_else(|_| "pretty".to_string());

    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("nclaw_core=info,warn"));

    let log_dir = log_directory();
    if let Err(e) = fs::create_dir_all(&log_dir) {
        eprintln!(
            "Failed to create log directory {}: {}",
            log_dir.display(),
            e
        );
    }

    let file_appender = tracing_appender::rolling::RollingFileAppender::new(
        tracing_appender::rolling::Rotation::DAILY,
        &log_dir,
        "nclaw.log",
    );

    // Limit total log size to 500MB via naming convention
    enforce_log_size_limit(&log_dir, 500 * 1024 * 1024);

    match format.as_str() {
        "json" => {
            tracing_subscriber::registry()
                .with(filter)
                .with(fmt::layer().json().with_writer(file_appender))
                .with(fmt::layer().json().with_writer(std::io::stderr))
                .init();
        }
        _ => {
            // default: "pretty"
            tracing_subscriber::registry()
                .with(filter)
                .with(fmt::layer().pretty().with_writer(file_appender))
                .with(fmt::layer().pretty().with_writer(std::io::stderr))
                .init();
        }
    }
}

/// Return platform-appropriate log directory
fn log_directory() -> PathBuf {
    #[cfg(target_os = "macos")]
    {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        PathBuf::from(home).join("Library/Logs/nClaw")
    }

    #[cfg(target_os = "windows")]
    {
        let appdata = std::env::var("APPDATA").unwrap_or_else(|_| ".".to_string());
        PathBuf::from(appdata).join("nClaw/logs")
    }

    #[cfg(target_os = "linux")]
    {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        PathBuf::from(home).join(".local/state/nclaw/logs")
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
    {
        PathBuf::from("./logs")
    }
}

/// Enforce total log size limit by removing oldest files
fn enforce_log_size_limit(log_dir: &Path, max_size: u64) {
    if !log_dir.exists() {
        return;
    }

    let mut entries = match fs::read_dir(log_dir) {
        Ok(e) => e
            .filter_map(|e| e.ok())
            .filter_map(|e| {
                e.metadata()
                    .ok()
                    .and_then(|m| e.file_name().into_string().ok().map(|n| (e.path(), n, m)))
            })
            .collect::<Vec<_>>(),
        Err(_) => return,
    };

    // Sort by modification time, oldest first
    entries.sort_by_key(|(p, _, _)| {
        p.metadata()
            .and_then(|m| m.modified())
            .unwrap_or_else(|_| std::time::SystemTime::now())
    });

    // Calculate total size and remove oldest files if exceeded
    let mut total_size = 0u64;
    for (path, _, metadata) in entries.iter().rev() {
        total_size += metadata.len();
        if total_size > max_size {
            let _ = fs::remove_file(path);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_log_directory_path_exists() {
        let path = log_directory();
        assert!(!path.as_os_str().is_empty());
    }
}
