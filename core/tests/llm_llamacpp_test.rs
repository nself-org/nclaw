//! LlamaCpp backend real-wiring tests (P102 S04).
//!
//! Covers: memory-guard rejection, GPU-layer configuration, sampling-param
//! propagation via streaming, and stream-yields-≥2-tokens happy path.
//!
//! All tests are feature-gated behind `cpu | metal | cuda | vulkan`. Run via:
//!
//!   NCLAW_TEST_GGUF_PATH=/path/to/tiny.gguf \
//!     cargo test --features cpu --test llm_llamacpp_test
//!
//! Tests that require a model are auto-skipped when `NCLAW_TEST_GGUF_PATH` is
//! not set, so the suite stays green in CI without a pre-cached model.

#![cfg(any(
    feature = "cpu",
    feature = "metal",
    feature = "cuda",
    feature = "vulkan"
))]

use libnclaw::backend::{GenOpts, LlmBackend};
use libnclaw::error::LlmError;
use libnclaw::llm::backend::llamacpp::LlamaCpp;
use std::io::Write as _;
use std::path::PathBuf;
use std::sync::Arc;

/// Build a default `GenOpts` for tests. Greedy by default for determinism.
fn opts(max_tokens: usize) -> GenOpts {
    GenOpts {
        model: "local".into(),
        max_tokens,
        temperature: 0.0,
        top_p: 1.0,
        stop_sequences: vec![],
    }
}

/// Resolve the test model path or `None` to signal "skip".
fn model_path() -> Option<PathBuf> {
    std::env::var("NCLAW_TEST_GGUF_PATH").ok().map(PathBuf::from)
}

// ---------------------------------------------------------------------------
// Configuration tests — do not require a model.
// ---------------------------------------------------------------------------

#[test]
fn n_gpu_layers_default_matches_feature() {
    // The default differs by compiled feature, but it must be exposed.
    let Ok(backend) = LlamaCpp::new() else {
        eprintln!("skipping n_gpu_layers_default_matches_feature: LlamaCpp::new failed (libllama missing?)");
        return;
    };
    let n = backend.n_gpu_layers();
    if cfg!(any(feature = "metal", feature = "cuda", feature = "vulkan")) {
        assert!(n > 0, "GPU feature should default to >0 layers, got {n}");
    } else {
        assert_eq!(n, 0, "CPU-only build should default to 0 GPU layers");
    }
}

#[test]
fn n_gpu_layers_builder_overrides_default() {
    let Ok(backend) = LlamaCpp::new() else {
        eprintln!("skipping n_gpu_layers_builder_overrides_default: LlamaCpp::new failed");
        return;
    };
    let configured = backend.with_n_gpu_layers(7);
    assert_eq!(configured.n_gpu_layers(), 7);
}

// ---------------------------------------------------------------------------
// Memory-guard rejection — uses a sparse "fake GGUF" file whose apparent size
// exceeds any realistic available RAM.
// ---------------------------------------------------------------------------

#[test]
fn memory_guard_rejects_oversized_model() {
    // Create a temp file: GGUF magic header + sparse 1 EiB hole. The OS reports
    // 1 EiB via `metadata().len()`, but no physical blocks are allocated.
    // Skip the test if the platform can't make a sparse file (most can).
    let dir = match tempfile::tempdir() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("skipping memory_guard_rejects_oversized_model: tempdir: {e}");
            return;
        }
    };
    let path = dir.path().join("oversized.gguf");
    let mut f = match std::fs::File::create(&path) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("skipping: create file: {e}");
            return;
        }
    };
    if f.write_all(b"GGUF").is_err() {
        eprintln!("skipping: write header failed");
        return;
    }
    // 1 EiB sparse hole. set_len does NOT allocate blocks on macOS/Linux.
    let huge: u64 = 1u64 << 60; // 1 EiB
    if f.set_len(huge).is_err() {
        eprintln!("skipping: set_len on sparse file unsupported on this platform");
        return;
    }
    drop(f);

    let Ok(mut backend) = LlamaCpp::new() else {
        eprintln!("skipping: LlamaCpp::new failed");
        return;
    };

    match backend.load_model(&path) {
        Err(LlmError::InsufficientMemory {
            required,
            available,
        }) => {
            assert!(
                required > available,
                "required {required} must exceed available {available}"
            );
        }
        Err(LlmError::ModelLoadFailed { reason }) => {
            // Acceptable if the platform has no memory probe (returned None)
            // and the underlying loader rejected the bogus file. Still a
            // controlled rejection — not an OOM panic.
            eprintln!(
                "memory_guard_rejects_oversized_model: no memory probe; got ModelLoadFailed({reason})"
            );
        }
        other => panic!(
            "expected InsufficientMemory or ModelLoadFailed for 1EiB file, got {other:?}"
        ),
    }
}

#[test]
fn invalid_magic_rejected_as_model_load_failed() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("not-gguf.bin");
    std::fs::write(&path, b"NOPE----").expect("write");

    let Ok(mut backend) = LlamaCpp::new() else {
        eprintln!("skipping invalid_magic_rejected: LlamaCpp::new failed");
        return;
    };
    match backend.load_model(&path) {
        Err(LlmError::ModelLoadFailed { reason }) => {
            assert!(
                reason.contains("not a GGUF"),
                "expected GGUF-magic error, got: {reason}"
            );
        }
        other => panic!("expected ModelLoadFailed, got {other:?}"),
    }
}

// ---------------------------------------------------------------------------
// Streaming + sampling tests — require a real model. Skipped without
// NCLAW_TEST_GGUF_PATH so CI without a cached model stays green.
// ---------------------------------------------------------------------------

#[tokio::test]
async fn stream_yields_at_least_two_tokens() {
    let Some(path) = model_path() else {
        eprintln!("skipping stream_yields_at_least_two_tokens: NCLAW_TEST_GGUF_PATH unset");
        return;
    };
    let mut backend = LlamaCpp::new().expect("LlamaCpp::new");
    backend.load_model(&path).expect("load_model");

    let backend = Arc::new(backend);
    let mut rx = Arc::clone(&backend).generate_stream("hello".into(), opts(8));

    let mut received: Vec<String> = Vec::new();
    while let Some(item) = rx.recv().await {
        match item {
            Ok(tok) => received.push(tok),
            Err(e) => panic!("stream error: {e}"),
        }
    }
    assert!(
        received.len() >= 2,
        "expected ≥2 streamed tokens, got {} (joined={:?})",
        received.len(),
        received.join("")
    );
}

#[tokio::test]
async fn stop_sequence_truncates_generation() {
    let Some(path) = model_path() else {
        eprintln!("skipping stop_sequence_truncates_generation: NCLAW_TEST_GGUF_PATH unset");
        return;
    };
    let mut backend = LlamaCpp::new().expect("LlamaCpp::new");
    backend.load_model(&path).expect("load_model");

    // Stop on the first emitted non-empty token's first character. We rely
    // on the backend honouring stop_sequences via accumulated-text suffix
    // matching, so we pre-run greedy once to learn what would come out, then
    // stop on a known prefix substring.
    let probe = backend
        .generate("hello", opts(4))
        .await
        .expect("probe generate");
    let joined = probe.tokens.join("");
    if joined.is_empty() {
        eprintln!("skipping stop_sequence test: probe produced no text");
        return;
    }
    // Pick the last char of the first detokenised piece as a stop sequence.
    let needle: String = joined.chars().take(1).collect();
    let mut stop_opts = opts(64);
    stop_opts.stop_sequences = vec![needle.clone()];

    let result = backend
        .generate("hello", stop_opts)
        .await
        .expect("stop generate");
    let out = result.tokens.join("");
    assert!(
        out.contains(&needle),
        "expected output to contain stop needle {needle:?}, got {out:?}"
    );
    assert_eq!(
        result.finish_reason, "stop",
        "expected finish_reason=stop when stop_sequences match"
    );
}

#[tokio::test]
async fn sampling_temperature_zero_is_deterministic() {
    let Some(path) = model_path() else {
        eprintln!("skipping sampling_temperature_zero_is_deterministic: NCLAW_TEST_GGUF_PATH unset");
        return;
    };
    let mut backend = LlamaCpp::new().expect("LlamaCpp::new");
    backend.load_model(&path).expect("load_model");

    let a = backend
        .generate("hello", opts(4))
        .await
        .expect("first generate");
    let b = backend
        .generate("hello", opts(4))
        .await
        .expect("second generate");
    assert_eq!(
        a.tokens.join(""),
        b.tokens.join(""),
        "temperature=0 must be deterministic across runs"
    );
}
