//! Integration test: model swap VRAM-leak verification (S19.T06 CR-C gate).
//!
//! Loops 10 consecutive swap cycles between two model paths and asserts that
//! VRAM usage at the end is no more than 50 MB above the pre-load baseline.
//!
//! This test requires:
//!   - A llama.cpp feature flag (`cpu | metal | cuda | vulkan`)
//!   - `integration_tests` feature
//!   - `NCLAW_TEST_GGUF_PATH` env var pointing to a valid (tiny) GGUF model
//!
//! When either env var or feature is absent the test prints a skip notice and
//! passes — it must never block the standard `cargo test` fast-path.
//!
//! Run manually:
//!   NCLAW_TEST_GGUF_PATH=/path/to/tiny.gguf \
//!     cargo test --features cpu,integration_tests \
//!     --test llm_swap_vram -- --nocapture
//!
//! The llama.cpp Drop guarantee (T06 AI Instruction §1 + §5):
//!   `LlamaModel::drop` calls `llama_free_model()` synchronously before
//!   returning. `LlamaContext::drop` calls `llama_free()`. No async work is
//!   deferred. This behaviour is documented in llama-cpp-2 src/model.rs and
//!   src/context.rs. If a future upstream release defers cleanup to a thread,
//!   we would need an explicit barrier here — tracked at
//!   https://github.com/utilityai/llama-cpp-rs (monitor for async Drop).

#[cfg(feature = "integration_tests")]
#[cfg(any(
    feature = "cpu",
    feature = "metal",
    feature = "cuda",
    feature = "vulkan"
))]
mod swap_vram {
    use libnclaw::llm::backend::llamacpp::LlamaCpp;
    use libnclaw::llm::telemetry::poll_memory;
    use std::path::PathBuf;

    /// Maximum allowed VRAM growth across 10 swap cycles, in MB.
    const VRAM_TOLERANCE_MB: u64 = 50;

    /// Number of swap cycles to perform.
    const SWAP_CYCLES: usize = 10;

    #[tokio::test]
    async fn swap_cycles_no_vram_leak() {
        // Resolve the model path from env — skip if not provided.
        let model_path = match std::env::var("NCLAW_TEST_GGUF_PATH") {
            Ok(p) => PathBuf::from(p),
            Err(_) => {
                eprintln!(
                    "skipping llm_swap_vram::swap_cycles_no_vram_leak: \
                     NCLAW_TEST_GGUF_PATH not set.\n\
                     Set it to a tiny valid .gguf path to run the VRAM-leak integration test.\n\
                     Example: NCLAW_TEST_GGUF_PATH=/path/to/tiny.gguf \\\n\
                     cargo test --features cpu,integration_tests --test llm_swap_vram"
                );
                return;
            }
        };

        if !model_path.exists() {
            eprintln!(
                "skipping llm_swap_vram: fixture path does not exist: {}",
                model_path.display()
            );
            return;
        }

        // Initialise the llama.cpp backend.
        let mut backend = match LlamaCpp::new() {
            Ok(b) => b,
            Err(e) => {
                eprintln!("skipping llm_swap_vram: LlamaCpp::new() failed: {e}");
                return;
            }
        };

        // --- Baseline: memory before any model is loaded ----------------------
        let baseline = poll_memory();
        let baseline_gpu_mb = baseline.gpu_used_mb;
        let baseline_ram_mb = baseline.ram_used_mb;

        eprintln!(
            "swap_vram baseline: GPU={} MB, RAM={} MB (source={})",
            baseline_gpu_mb, baseline_ram_mb, baseline.source
        );

        // --- Swap loop --------------------------------------------------------
        for cycle in 0..SWAP_CYCLES {
            // Load model.
            backend
                .load_model(&model_path)
                .unwrap_or_else(|e| panic!("cycle {cycle}: load_model failed: {e}"));

            let mid = poll_memory();
            eprintln!(
                "  cycle {cycle} loaded:   GPU={} MB, RAM={} MB",
                mid.gpu_used_mb, mid.ram_used_mb
            );

            // Unload model — Drop is synchronous in llama-cpp-2.
            backend.unload_model();

            // Brief settle: give the OS time to reclaim pages.
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;

            let after = poll_memory();
            eprintln!(
                "  cycle {cycle} unloaded: GPU={} MB, RAM={} MB",
                after.gpu_used_mb, after.ram_used_mb
            );
        }

        // --- Final VRAM assertion --------------------------------------------
        let final_snap = poll_memory();
        let final_gpu_mb = final_snap.gpu_used_mb;
        let final_ram_mb = final_snap.ram_used_mb;

        eprintln!(
            "swap_vram final:    GPU={} MB, RAM={} MB",
            final_gpu_mb, final_ram_mb
        );

        // GPU VRAM check (primary CR-C gate).
        let gpu_delta = final_gpu_mb.saturating_sub(baseline_gpu_mb);
        assert!(
            gpu_delta <= VRAM_TOLERANCE_MB,
            "VRAM leak detected after {} swap cycles: \
             baseline={} MB, final={} MB, delta={} MB (tolerance={} MB)",
            SWAP_CYCLES,
            baseline_gpu_mb,
            final_gpu_mb,
            gpu_delta,
            VRAM_TOLERANCE_MB,
        );

        // RAM check — secondary, wider tolerance (OS may cache pages).
        let ram_delta = final_ram_mb.saturating_sub(baseline_ram_mb);
        assert!(
            ram_delta <= VRAM_TOLERANCE_MB * 4,
            "RAM leak detected after {} swap cycles: \
             baseline={} MB, final={} MB, delta={} MB",
            SWAP_CYCLES,
            baseline_ram_mb,
            final_ram_mb,
            ram_delta,
        );

        eprintln!(
            "PASS: GPU delta={gpu_delta} MB, RAM delta={ram_delta} MB after {SWAP_CYCLES} cycles \
             (tolerance={VRAM_TOLERANCE_MB} MB GPU / {} MB RAM)",
            VRAM_TOLERANCE_MB * 4
        );
    }

    /// Sanity check: `unload_model` on an already-unloaded backend is a no-op.
    #[test]
    fn unload_model_idempotent() {
        let mut backend = match LlamaCpp::new() {
            Ok(b) => b,
            Err(e) => {
                eprintln!("skipping unload_model_idempotent: {e}");
                return;
            }
        };
        // Call unload twice without load — must not panic.
        backend.unload_model();
        backend.unload_model();
    }
}

// When feature flags are absent, compile a stub that always passes.
#[cfg(not(feature = "integration_tests"))]
mod swap_vram_disabled {
    #[test]
    fn swap_vram_disabled_notice() {
        // This test is intentionally empty — the swap VRAM integration test
        // is disabled when `integration_tests` feature is off. Enable it with:
        //   cargo test --features integration_tests,cpu --test llm_swap_vram
        eprintln!(
            "llm_swap_vram: integration_tests feature not enabled — test is a no-op in standard CI."
        );
    }
}
