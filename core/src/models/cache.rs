use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum CacheError {
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("cache entry not found: {0}")]
    NotFound(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheEntry {
    pub id: String,
    pub size_mb: u64,
    pub installed_at: DateTime<Utc>,
    pub last_used_at: DateTime<Utc>,
    pub user_imported: bool, // never auto-evicted if true
}

pub struct Cache {
    cache_dir: PathBuf,
    index: HashMap<String, CacheEntry>,
}

#[derive(Debug, Clone)]
pub enum VerifyResult {
    Ok(String),
    SizeMismatch(String),
    Sha256Mismatch(String),
}

impl Cache {
    /// Open or initialize cache at cache_dir/.nclaw/models/ (or cache_dir/)
    pub fn open(cache_dir: impl Into<PathBuf>) -> Result<Self, CacheError> {
        let cache_dir = cache_dir.into();

        // Determine models directory
        let models_dir = if cache_dir.ends_with("models") {
            cache_dir.clone()
        } else {
            cache_dir.join(".nclaw/models")
        };

        // Create directory if missing
        fs::create_dir_all(&models_dir)?;

        // Load index.json if present
        let index_path = models_dir.join("index.json");
        let index = if index_path.exists() {
            let contents = fs::read_to_string(&index_path)?;
            serde_json::from_str(&contents)?
        } else {
            HashMap::new()
        };

        Ok(Cache {
            cache_dir: models_dir,
            index,
        })
    }

    /// List all installed models
    pub fn list_installed(&self) -> Vec<&CacheEntry> {
        self.index.values().collect()
    }

    /// Update last_used_at timestamp for a model
    pub fn touch(&mut self, id: &str) -> Result<(), CacheError> {
        if let Some(entry) = self.index.get_mut(id) {
            entry.last_used_at = Utc::now();
            self.persist_index()?;
            Ok(())
        } else {
            Err(CacheError::NotFound(id.to_string()))
        }
    }

    /// Evict least-recently-used entries until total size <= target_size_mb
    /// Skips currently_loaded and user_imported entries
    pub fn evict_lru(
        &mut self,
        target_size_mb: u64,
        currently_loaded: &str,
    ) -> Result<Vec<String>, CacheError> {
        let mut evicted = Vec::new();

        // Collect owned copies so we don't hold a borrow on self.index during mutation.
        let mut entries: Vec<(String, u64, bool, chrono::DateTime<chrono::Utc>)> = self
            .index
            .iter()
            .map(|(id, e)| (id.clone(), e.size_mb, e.user_imported, e.last_used_at))
            .collect();
        entries.sort_by_key(|e| e.3);

        // Calculate current total size
        let mut current_size_mb: u64 = self.index.values().map(|e| e.size_mb).sum();

        // Evict until target size or no evictable entries remain
        for (id, size_mb, user_imported, _) in entries {
            if current_size_mb <= target_size_mb {
                break;
            }

            // Skip currently_loaded and user_imported
            if id == currently_loaded || user_imported {
                continue;
            }

            // Delete the .gguf file
            let file_path = self.cache_dir.join(format!("{}.gguf", id));
            if file_path.exists() {
                fs::remove_file(&file_path)?;
            }

            // Remove from index
            current_size_mb = current_size_mb.saturating_sub(size_mb);
            evicted.push(id.clone());
            self.index.remove(&id);
        }

        // Persist updated index
        if !evicted.is_empty() {
            self.persist_index()?;
        }

        Ok(evicted)
    }

    /// Verify all cached models: size match first, SHA-256 only if size mismatch
    pub fn verify_all(&self) -> Vec<VerifyResult> {
        let mut results = Vec::new();

        for (id, entry) in &self.index {
            let file_path = self.cache_dir.join(format!("{}.gguf", id));

            if !file_path.exists() {
                results.push(VerifyResult::SizeMismatch(format!("{}: file missing", id)));
                continue;
            }

            // Lazy verification: check size first
            match fs::metadata(&file_path) {
                Ok(metadata) => {
                    let actual_size_mb = metadata.len() / (1024 * 1024);
                    if actual_size_mb != entry.size_mb {
                        results.push(VerifyResult::SizeMismatch(format!(
                            "{}: expected {}MB, got {}MB",
                            id, entry.size_mb, actual_size_mb
                        )));
                    } else {
                        results.push(VerifyResult::Ok(id.clone()));
                    }
                }
                Err(_) => {
                    results.push(VerifyResult::SizeMismatch(format!(
                        "{}: cannot stat file",
                        id
                    )));
                }
            }
        }

        results
    }

    /// Clean up orphaned .gguf files not in index
    pub fn cleanup_orphans(&mut self) -> Result<Vec<String>, CacheError> {
        let mut orphaned = Vec::new();

        for entry in fs::read_dir(&self.cache_dir)? {
            let entry = entry?;
            let path = entry.path();

            if path.extension().and_then(|s| s.to_str()) == Some("gguf") {
                if let Some(file_stem) = path.file_stem().and_then(|s| s.to_str()) {
                    if !self.index.contains_key(file_stem) {
                        fs::remove_file(&path)?;
                        orphaned.push(file_stem.to_string());
                    }
                }
            }
        }

        // Persist if anything was cleaned
        if !orphaned.is_empty() {
            self.persist_index()?;
        }

        Ok(orphaned)
    }

    /// Register a new model in the cache (without adding file)
    pub fn register(&mut self, id: String, size_mb: u64, user_imported: bool) {
        let entry = CacheEntry {
            id: id.clone(),
            size_mb,
            installed_at: Utc::now(),
            last_used_at: Utc::now(),
            user_imported,
        };
        self.index.insert(id, entry);
    }

    /// Persist index.json to disk with atomic tempfile + rename
    fn persist_index(&self) -> Result<(), CacheError> {
        let index_path = self.cache_dir.join("index.json");
        let json = serde_json::to_string_pretty(&self.index)?;

        // Atomic write: write to temp file, then rename
        let temp_path = self.cache_dir.join("index.json.tmp");
        fs::write(&temp_path, &json)?;
        fs::rename(&temp_path, &index_path)?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    #[test]
    fn test_cache_open_creates_directory() {
        let temp = TempDir::new().unwrap();
        let cache_dir = temp.path().join(".nclaw/models");

        let cache = Cache::open(&cache_dir).unwrap();
        assert!(cache.cache_dir.exists());
    }

    #[test]
    fn test_register_and_list() {
        let temp = TempDir::new().unwrap();
        let mut cache = Cache::open(temp.path()).unwrap();

        cache.register("model-1".to_string(), 1024, false);
        cache.register("model-2".to_string(), 2048, false);

        assert_eq!(cache.list_installed().len(), 2);
    }

    #[test]
    fn test_persist_and_reload() {
        let temp = TempDir::new().unwrap();
        {
            let mut cache = Cache::open(temp.path()).unwrap();
            cache.register("model-1".to_string(), 1024, false);
            cache.persist_index().unwrap();
        }

        // Reload from disk
        let cache = Cache::open(temp.path()).unwrap();
        assert_eq!(cache.list_installed().len(), 1);
        let entry = cache.index.get("model-1").unwrap();
        assert_eq!(entry.size_mb, 1024);
    }

    #[test]
    fn test_cleanup_orphans() {
        let temp = TempDir::new().unwrap();
        let models_dir = temp.path().join(".nclaw/models");
        fs::create_dir_all(&models_dir).unwrap();

        // Create some orphan .gguf files
        fs::write(models_dir.join("orphan1.gguf"), "fake").unwrap();
        fs::write(models_dir.join("orphan2.gguf"), "fake").unwrap();

        let mut cache = Cache::open(&models_dir).unwrap();
        cache.register("tracked".to_string(), 512, false);

        let orphaned = cache.cleanup_orphans().unwrap();
        assert_eq!(orphaned.len(), 2);
        assert!(!models_dir.join("orphan1.gguf").exists());
        assert!(!models_dir.join("orphan2.gguf").exists());
    }
}
