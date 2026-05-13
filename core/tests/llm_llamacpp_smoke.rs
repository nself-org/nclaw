//! Smoke test for the LlamaCpp FFI backend.
//!
//! Gated behind `#[cfg(feature = "cpu")]` — only compiled and run when the
//! llama.cpp FFI feature is enabled.
//!
//! If `NCLAW_TEST_GGUF_PATH` is set in the environment, the test loads the
//! model, tokenises "hello", generates 5 tokens, and asserts a non-empty
//! result. If the env var is absent the test prints a skip notice and passes.
//!
//! Run with:
//!   NCLAW_TEST_GGUF_PATH=/path/to/model.gguf cargo test --features cpu \
//!       --test llm_llamacpp_smoke

#[cfg(all(
    test,
    any(
        feature = "cpu",
        feature = "metal",
        feature = "cuda",
        feature = "vulkan"
    )
))]
mod llamacpp_smoke {
    use libnclaw::backend::{GenOpts, LlmBackend};
    use libnclaw::llm::backend::llamacpp::LlamaCpp;
    use std::path::PathBuf;

    #[tokio::test]
    async fn smoke_generate_five_tokens() {
        let gguf_path = match std::env::var("NCLAW_TEST_GGUF_PATH") {
            Ok(p) => PathBuf::from(p),
            Err(_) => {
                eprintln!(
                    "skipping llm_llamacpp_smoke: NCLAW_TEST_GGUF_PATH not set. \
                     Set it to a valid .gguf model path to run the live test."
                );
                return;
            }
        };

        // Initialise backend
        let mut backend = LlamaCpp::new().expect("LlamaCpp::new should succeed when feature is on");

        // Load model — validate GGUF magic + mmap
        backend
            .load_model(&gguf_path)
            .unwrap_or_else(|e| panic!("load_model failed: {e}"));

        // Generate 5 tokens from a minimal prompt
        let opts = GenOpts {
            model: "local".into(),
            max_tokens: 5,
            temperature: 0.0, // greedy for determinism
            top_p: 1.0,
            stop_sequences: vec![],
        };

        let result = backend
            .generate("hello", opts)
            .await
            .unwrap_or_else(|e| panic!("generate failed: {e}"));

        assert!(
            !result.tokens.is_empty(),
            "expected at least one token, got zero"
        );

        // Unload and verify a second load is safe (memory-swap isolation)
        backend.unload_model();
        backend
            .load_model(&gguf_path)
            .unwrap_or_else(|e| panic!("second load_model failed: {e}"));
        backend.unload_model();
    }

    #[test]
    fn provider_string_correct() {
        // Verifies the provider string without loading a model.
        // LlamaCpp::new() may fail if libllama.so is missing in CI — handle gracefully.
        match LlamaCpp::new() {
            Ok(b) => assert_eq!(b.provider(), "llamacpp"),
            Err(e) => eprintln!("skipping provider_string_correct: {e}"),
        }
    }
}

#[cfg(all(
    test,
    not(any(
        feature = "cpu",
        feature = "metal",
        feature = "cuda",
        feature = "vulkan"
    ))
))]
mod llamacpp_stub_smoke {
    use libnclaw::llm::backend::llamacpp::LlamaCppBackend;

    #[test]
    fn stub_new_returns_err() {
        let err = LlamaCppBackend::new().unwrap_err();
        let msg = err.to_string();
        assert!(
            msg.contains("llama.cpp not compiled in"),
            "expected no-feature error message, got: {msg}"
        );
    }
}
