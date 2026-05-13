//! llama.cpp FFI backend — feature-gated via `cpu | metal | cuda | vulkan`.
//!
//! When any FFI feature is enabled, `LlamaCpp` wraps `llama_cpp_2` model/context
//! types and implements `LlmBackend`. When no FFI feature is compiled in, every
//! method returns `LlmError::InternalError("llama.cpp not compiled in ...")`.
//!
//! Memory-swap safety: `unload_model` drops the model field (calling the
//! `llama_cpp_2` destructor) **before** returning. A subsequent `load_model` is
//! therefore fully isolated — model allocations never overlap in host memory.

// ============================================================================
// Feature-gated implementation
// ============================================================================

#[cfg(any(
    feature = "cpu",
    feature = "metal",
    feature = "cuda",
    feature = "vulkan"
))]
mod ffi_impl {
    use crate::backend::{GenOpts, LlmBackend, TokenStream};
    use crate::error::LlmError;
    use std::io::Read as _;
    use std::path::Path;

    // llama-cpp-2 re-exports the high-level API under these paths.
    // If the crate bumps its API, the compiler will point here.
    use llama_cpp_2::{
        context::params::LlamaContextParams,
        llama_backend::LlamaBackend,
        model::{params::LlamaModelParams, LlamaModel},
    };

    // -------------------------------------------------------------------------
    // LlamaCpp — holds an optional loaded model
    // -------------------------------------------------------------------------

    pub struct LlamaCpp {
        backend: LlamaBackend,
        model: Option<LlamaModel>,
        context_size: u32,
    }

    impl LlamaCpp {
        /// Initialise the llama.cpp global backend (must be called once per process).
        /// Subsequent calls after the first are no-ops on the C++ side.
        pub fn new() -> Result<Self, LlmError> {
            let backend = LlamaBackend::init()
                .map_err(|e| LlmError::InternalError(format!("llama_backend_init: {e}")))?;
            Ok(Self {
                backend,
                model: None,
                context_size: 4096,
            })
        }

        /// Validate GGUF magic bytes, then load the model file into VRAM/RAM.
        pub fn load_model(&mut self, path: &Path) -> Result<(), LlmError> {
            // Verify GGUF magic ("GGUF" as 4 ASCII bytes).
            let mut header = [0u8; 4];
            std::fs::File::open(path)
                .map_err(|e| LlmError::InternalError(format!("open: {e}")))?
                .read_exact(&mut header)
                .map_err(|e| LlmError::InternalError(format!("read header: {e}")))?;
            if &header != b"GGUF" {
                return Err(LlmError::InternalError(format!(
                    "not a GGUF file (magic={:?})",
                    header
                )));
            }

            // Drop any previously loaded model before loading a new one.
            // This ensures allocations never overlap (memory-swap safety).
            self.model = None;

            let model_params = LlamaModelParams::default();
            let model = LlamaModel::load_from_file(&self.backend, path, &model_params)
                .map_err(|e| LlmError::ModelNotFound(format!("load_from_file: {e}")))?;
            self.model = Some(model);
            Ok(())
        }

        /// Unload the current model, freeing all associated memory before returning.
        pub fn unload_model(&mut self) {
            // Explicit drop before the function returns — required by acceptance criteria.
            drop(self.model.take());
        }

        /// Run a simple greedy decode for `max_tokens` steps and collect token strings.
        fn decode(&self, prompt: &str, opts: &GenOpts) -> Result<Vec<String>, LlmError> {
            let model = self.model.as_ref().ok_or_else(|| {
                LlmError::InternalError("no model loaded — call load_model first".into())
            })?;

            let ctx_params = LlamaContextParams::default().with_n_ctx(
                std::num::NonZeroU32::new(self.context_size)
                    .expect("context_size is non-zero at init"),
            );
            let mut ctx = model
                .new_context(&self.backend, ctx_params)
                .map_err(|e| LlmError::InternalError(format!("new_context: {e}")))?;

            // Tokenise prompt
            let tokens_list = model
                .str_to_token(prompt, llama_cpp_2::model::AddBos::Always)
                .map_err(|e| LlmError::InternalError(format!("tokenise: {e}")))?;

            let n_ctx = ctx.n_ctx() as usize;
            let n_kv_req = tokens_list.len() + opts.max_tokens;
            if n_kv_req > n_ctx {
                return Err(LlmError::TokenLimitExceeded {
                    requested: n_kv_req,
                    limit: n_ctx,
                });
            }

            // Build the initial batch
            let mut batch = llama_cpp_2::llama_batch::LlamaBatch::new(512, 1);
            for (i, &tok) in tokens_list.iter().enumerate() {
                let is_last = i == tokens_list.len() - 1;
                batch
                    .add(tok, i as i32, &[0], is_last)
                    .map_err(|e| LlmError::InternalError(format!("batch add: {e}")))?;
            }

            ctx.decode(&mut batch)
                .map_err(|e| LlmError::InternalError(format!("decode: {e}")))?;

            let mut result = Vec::with_capacity(opts.max_tokens);
            let mut n_cur = batch.n_tokens();

            for _ in 0..opts.max_tokens {
                let candidates = ctx.candidates_ith(batch.n_tokens() - 1);
                let mut candidates_p =
                    llama_cpp_2::token::data_array::LlamaTokenDataArray::from_iter(
                        candidates, false,
                    );
                let new_token = ctx.sample_token_greedy(&mut candidates_p);

                // EOS — stop generation
                if model.is_eog_token(new_token) {
                    break;
                }

                let piece = model
                    .token_to_str(new_token, llama_cpp_2::model::Special::Tokenize)
                    .map_err(|e| LlmError::InternalError(format!("token_to_str: {e}")))?;
                result.push(piece);

                // Stop sequences check
                let so_far = result.join("");
                if opts
                    .stop_sequences
                    .iter()
                    .any(|s| so_far.ends_with(s.as_str()))
                {
                    break;
                }

                batch.clear();
                batch
                    .add(new_token, n_cur, &[0], true)
                    .map_err(|e| LlmError::InternalError(format!("batch add next: {e}")))?;
                n_cur += 1;

                ctx.decode(&mut batch)
                    .map_err(|e| LlmError::InternalError(format!("decode next: {e}")))?;
            }

            Ok(result)
        }
    }

    // -------------------------------------------------------------------------
    // LlmBackend impl
    // -------------------------------------------------------------------------

    #[async_trait::async_trait]
    impl LlmBackend for LlamaCpp {
        async fn generate(&self, prompt: &str, opts: GenOpts) -> Result<TokenStream, LlmError> {
            let tokens = self.decode(prompt, &opts)?;
            let finish_reason = if tokens.len() < opts.max_tokens {
                "stop".into()
            } else {
                "length".into()
            };
            Ok(TokenStream {
                tokens,
                finish_reason,
            })
        }

        async fn embed(&self, text: &str) -> Result<Vec<f32>, LlmError> {
            let model = self.model.as_ref().ok_or_else(|| {
                LlmError::InternalError("no model loaded — call load_model first".into())
            })?;

            // llama_cpp_2 exposes embeddings via LlamaModel::embeddings_ith after a
            // forward pass with embeddings enabled. This requires a separate context
            // configured with `embeddings(true)`. Scaffold provided here; the caller
            // is expected to call load_model with an embedding-capable GGUF first.
            let ctx_params = LlamaContextParams::default()
                .with_n_ctx(std::num::NonZeroU32::new(512).unwrap())
                .with_embeddings(true);
            let mut ctx = model
                .new_context(&self.backend, ctx_params)
                .map_err(|e| LlmError::InternalError(format!("embed context: {e}")))?;

            let tokens = model
                .str_to_token(text, llama_cpp_2::model::AddBos::Always)
                .map_err(|e| LlmError::InternalError(format!("embed tokenise: {e}")))?;

            let mut batch = llama_cpp_2::llama_batch::LlamaBatch::new(512, 1);
            for (i, &tok) in tokens.iter().enumerate() {
                let is_last = i == tokens.len() - 1;
                batch
                    .add(tok, i as i32, &[0], is_last)
                    .map_err(|e| LlmError::InternalError(format!("embed batch: {e}")))?;
            }

            ctx.decode(&mut batch)
                .map_err(|e| LlmError::InternalError(format!("embed decode: {e}")))?;

            let emb = ctx
                .embeddings_seq_ith(0)
                .map_err(|e| LlmError::InternalError(format!("embeddings_seq_ith: {e}")))?;
            Ok(emb.to_vec())
        }

        fn supports_streaming(&self) -> bool {
            // Streaming is handled by StreamingGenerator in llm/stream.rs which drives
            // the batch generate() call token-by-token. Native llama.cpp streaming
            // (token-by-token decode loop) is available via load_model + decode directly.
            true
        }

        fn provider(&self) -> &str {
            "llamacpp"
        }
    }

    // Re-export as the canonical public name for this module.
    pub use LlamaCpp as LlamaCppBackend;
}

// ============================================================================
// No-FFI stub (default when no feature is enabled via --no-default-features)
// ============================================================================

#[cfg(not(any(
    feature = "cpu",
    feature = "metal",
    feature = "cuda",
    feature = "vulkan"
)))]
mod no_ffi {
    use crate::backend::{GenOpts, LlmBackend, TokenStream};
    use crate::error::LlmError;

    const NO_FEATURE_MSG: &str =
        "llama.cpp not compiled in — enable one of: cpu | metal | cuda | vulkan";

    pub struct LlamaCppBackend;

    impl LlamaCppBackend {
        pub fn new() -> Result<Self, LlmError> {
            Err(LlmError::InternalError(NO_FEATURE_MSG.into()))
        }
    }

    #[async_trait::async_trait]
    impl LlmBackend for LlamaCppBackend {
        async fn generate(&self, _prompt: &str, _opts: GenOpts) -> Result<TokenStream, LlmError> {
            Err(LlmError::InternalError(NO_FEATURE_MSG.into()))
        }

        async fn embed(&self, _text: &str) -> Result<Vec<f32>, LlmError> {
            Err(LlmError::InternalError(NO_FEATURE_MSG.into()))
        }

        fn supports_streaming(&self) -> bool {
            false
        }

        fn provider(&self) -> &str {
            "llamacpp-stub"
        }
    }
}

// ============================================================================
// Public surface
// ============================================================================

#[cfg(any(
    feature = "cpu",
    feature = "metal",
    feature = "cuda",
    feature = "vulkan"
))]
pub use ffi_impl::LlamaCppBackend;

#[cfg(any(
    feature = "cpu",
    feature = "metal",
    feature = "cuda",
    feature = "vulkan"
))]
pub use ffi_impl::LlamaCpp;

#[cfg(not(any(
    feature = "cpu",
    feature = "metal",
    feature = "cuda",
    feature = "vulkan"
)))]
pub use no_ffi::LlamaCppBackend;
