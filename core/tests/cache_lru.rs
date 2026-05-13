use libnclaw::models::cache::Cache;
use std::fs;
use tempfile::TempDir;

#[test]
fn test_lru_eviction_respects_currently_loaded() {
    let temp = TempDir::new().unwrap();
    let models_dir = temp.path();

    let mut cache = Cache::open(models_dir).unwrap();

    // Pre-populate with 5 fake .gguf files (1GB each = 1024MB)
    for i in 1..=5 {
        cache.register(format!("model-{}", i), 1024, false);
    }
    cache.persist_index().unwrap();

    // Create actual files
    for i in 1..=5 {
        let file_path = models_dir
            .join(".nclaw/models")
            .join(format!("model-{}.gguf", i));
        fs::write(&file_path, vec![0; 1024 * 1024 * 1024]).unwrap();
    }

    // Simulate aging: update last_used_at to be spaced 1 hour apart (oldest to newest)
    // Note: in a real scenario, these would be set at install time and updated on use
    let now = chrono::Utc::now();
    for (i, entry) in cache.list_installed().iter().enumerate() {
        if let Some(cached_entry) = cache.index.get_mut(&entry.id) {
            cached_entry.last_used_at =
                now - chrono::Duration::hours((5 - i as i64 - 1) * 1);
        }
    }
    cache.persist_index().unwrap();

    // Evict LRU models to target 2GB (2048MB), excluding "model-3"
    let evicted = cache.evict_lru(2048, "model-3").unwrap();

    // Should evict 3 oldest models (model-1, model-2, model-4, model-5)
    // but NOT model-3 (currently_loaded)
    // Total remaining: model-3 (1024) + 1 other = max 2048
    assert_eq!(evicted.len(), 3);
    assert!(!evicted.contains(&"model-3".to_string()));

    // Verify remaining cache size
    let remaining_size: u64 = cache
        .list_installed()
        .iter()
        .map(|e| e.size_mb)
        .sum();
    assert!(remaining_size <= 2048);
}

#[test]
fn test_user_imported_never_evicted() {
    let temp = TempDir::new().unwrap();
    let models_dir = temp.path();

    let mut cache = Cache::open(models_dir).unwrap();

    // Register 3 models: 2 auto-downloaded, 1 user-imported
    cache.register("model-1".to_string(), 1024, false);
    cache.register("model-2".to_string(), 1024, false);
    cache.register("user-custom".to_string(), 512, true); // user_imported=true
    cache.persist_index().unwrap();

    // Create files
    for name in &["model-1", "model-2", "user-custom"] {
        let file_path = models_dir
            .join(".nclaw/models")
            .join(format!("{}.gguf", name));
        fs::write(&file_path, vec![0; 512 * 1024 * 1024]).unwrap();
    }

    // Evict to target 512MB (only user-custom fits)
    let evicted = cache.evict_lru(512, "").unwrap();

    // Should evict model-1 and model-2, but NOT user-custom
    assert_eq!(evicted.len(), 2);
    assert!(!evicted.contains(&"user-custom".to_string()));
    assert!(evicted.contains(&"model-1".to_string()) || evicted.contains(&"model-2".to_string()));

    // user-custom should still be in index
    assert!(cache.index.contains_key("user-custom"));
}

#[test]
fn test_cleanup_orphans() {
    let temp = TempDir::new().unwrap();
    let models_dir = temp.path().join(".nclaw/models");
    fs::create_dir_all(&models_dir).unwrap();

    // Create tracked and orphan .gguf files
    fs::write(models_dir.join("tracked.gguf"), "fake").unwrap();
    fs::write(models_dir.join("orphan1.gguf"), "fake").unwrap();
    fs::write(models_dir.join("orphan2.gguf"), "fake").unwrap();

    let mut cache = Cache::open(&models_dir).unwrap();
    cache.register("tracked".to_string(), 512, false);
    cache.persist_index().unwrap();

    // Clean up orphans
    let orphaned = cache.cleanup_orphans().unwrap();

    assert_eq!(orphaned.len(), 2);
    assert!(orphaned.contains(&"orphan1".to_string()));
    assert!(orphaned.contains(&"orphan2".to_string()));

    // Verify orphans are deleted
    assert!(!models_dir.join("orphan1.gguf").exists());
    assert!(!models_dir.join("orphan2.gguf").exists());

    // Tracked should still exist
    assert!(models_dir.join("tracked.gguf").exists());
}

#[test]
fn test_verify_all_size_mismatch() {
    let temp = TempDir::new().unwrap();
    let models_dir = temp.path();

    let mut cache = Cache::open(models_dir).unwrap();
    cache.register("model-1".to_string(), 1024, false); // Expect 1024MB
    cache.persist_index().unwrap();

    // Create file with 512MB (half expected size)
    let file_path = models_dir
        .join(".nclaw/models")
        .join("model-1.gguf");
    fs::write(&file_path, vec![0; 512 * 1024 * 1024]).unwrap();

    // Verify all
    let results = cache.verify_all();
    assert_eq!(results.len(), 1);

    // Should report size mismatch
    match &results[0] {
        libnclaw::models::cache::VerifyResult::SizeMismatch(msg) => {
            assert!(msg.contains("expected 1024MB"));
            assert!(msg.contains("got 512MB"));
        }
        _ => panic!("Expected SizeMismatch"),
    }
}

#[test]
fn test_touch_updates_last_used() {
    let temp = TempDir::new().unwrap();
    let models_dir = temp.path();

    let mut cache = Cache::open(models_dir).unwrap();
    cache.register("model-1".to_string(), 1024, false);

    let original_used = cache.index.get("model-1").unwrap().last_used_at;

    // Sleep a tiny bit to ensure time difference
    std::thread::sleep(std::time::Duration::from_millis(10));

    // Touch the model
    cache.touch("model-1").unwrap();

    let updated_used = cache.index.get("model-1").unwrap().last_used_at;
    assert!(updated_used > original_used);
}

#[test]
fn test_persist_and_reload_roundtrip() {
    let temp = TempDir::new().unwrap();

    // Write cache
    {
        let mut cache = Cache::open(temp.path()).unwrap();
        cache.register("model-1".to_string(), 2048, true);
        cache.register("model-2".to_string(), 1024, false);
        cache.persist_index().unwrap();
    }

    // Reload cache
    let cache = Cache::open(temp.path()).unwrap();
    assert_eq!(cache.list_installed().len(), 2);

    let model1 = cache.index.get("model-1").unwrap();
    assert_eq!(model1.size_mb, 2048);
    assert!(model1.user_imported);

    let model2 = cache.index.get("model-2").unwrap();
    assert_eq!(model2.size_mb, 1024);
    assert!(!model2.user_imported);
}
