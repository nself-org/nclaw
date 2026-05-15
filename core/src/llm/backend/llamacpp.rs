//! llama.cpp FFI backend — feature-gated via `cpu | metal | cuda | vulkan`.
//!
//! Real end-to-end integration with `llama_cpp_2`:
//!
//! - GGUF model load with explicit `n_gpu_layers` (CPU-fallback when GPU
//!   feature is not compiled in).
//! - Memory-guard refuses to load when `file_size × 1.2 > available_system_ram`
//!   and returns the typed `LlmError::InsufficientMemory { required, available }`
//!   instead of attempting an OOM-prone load.
//! - Sampling chain: temperature, top-p, top-k, max-tokens, stop-sequences all
//!   honoured. Built on `LlamaSampler::chain_simple([top_k, top_p, temp, dist])`.
//! - Streaming: `generate_stream` returns an `mpsc::Receiver<Result<String, LlmError>>`
//!   that yields tokens token-by-token as they decode. Batch `generate` reuses
//!   the same decode loop and collects.
//!
//! Memory-swap safety: `unload_model` drops the model field (calling the
//! `llama_cpp_2` destructor) **before** returning. A subsequent `load_model` is
//! therefore fully isolated — model allocations never overlap in host memory.

// ============================================================================
// Memory-guard helper — portable best-effort available-RAM probe.
// ============================================================================

/// Return best-effort available physical memory in bytes.
///
/// Returns `None` when the platform-specific probe is unavailable; callers
/// should treat that as "skip the guard" rather than failure.
#[allow(dead_code)]
fn available_memory_bytes() -> Option<u64> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        // hw.memsize gives total physical RAM. There is no portable "available"
        // sysctl across macOS versions without host_statistics64; total is a
        // safe upper bound for the guard (the guard refuses when required
        // exceeds total, which is the only case we can be certain of).
        let mut value: u64 = 0;
        let mut len = std::mem::size_of::<u64>();
        let key = std::ffi::CString::new("hw.memsize").ok()?;
        let rc = unsafe {
            libc::sysctlbyname(
                key.as_ptr(),
                &mut value as *mut u64 as *mut libc::c_void,
                &mut len,
                std::ptr::null_mut(),
                0,
            )
        };
        if rc == 0 && value > 0 {
            return Some(value);
        }
        None
    }

    #[cfg(target_os = "linux")]
    {
        // Parse /proc/meminfo's MemAvailable line. No syscall, no extra dep.
        let s = std::fs::read_to_string("/proc/meminfo").ok()?;
        for line in s.lines() {
            if let Some(rest) = line.strip_prefix("MemAvailable:") {
                let kb: u64 = rest.trim().split_whitespace().next()?.parse().ok()?;
                return Some(kb.saturating_mul(1024));
            }
        }
        None
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "linux")))]
    {
        None
    }
}

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
    use super::available_memory_bytes;
    use crate::backend::{GenOpts, LlmBackend, TokenStream};
    use crate::error::LlmError;
    use std::io::Read as _;
    use std::path::Path;
    use tokio::sync::mpsc;

    // llama-cpp-2 re-exports the high-level API under these paths.
    // If the crate bumps its API, the compiler will point here.
    use llama_cpp_2::{
        context::params::LlamaContextParams,
        llama_backend::LlamaBackend,
        model::{params::LlamaModelParams, LlamaModel},
        sampling::LlamaSampler,
    };

    /// Safety headroom multiplier — refuse to load when file_size × this exceeds
    /// available memory. 1.2 covers KV cache + scratch overhead beyond model weights.
    const MEMORY_HEADROOM_MULT: f64 = 1.2;

    /// Default GPU layer count by feature flag.
    #[allow(dead_code)]
    const fn default_n_gpu_layers() -> u32 {
        if cfg!(any(feature = "metal", feature = "cuda", feature = "vulkan")) {
            999 // offload everything when GPU is available
        } else {
            0 // CPU-only build: no GPU layers
        }
    }

    // -------------------------------------------------------------------------
    // LlamaCpp — holds an optional loaded model + sampling/runtime config.
    // -------------------------------------------------------------------------

    pub struct LlamaCpp {
        backend: LlamaBackend,
        model: Option<LlamaModel>,
        context_size: u32,
        n_gpu_layers: u32,
        /// Sampling RNG seed for `dist()` — overridable for deterministic tests.
        seed: u32,
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
                n_gpu_layers: default_n_gpu_layers(),
                seed: 1234,
            })
        }

        /// Configure number of model layers offloaded to GPU. `0` = CPU only.
        /// `999` (or any value larger than the model's layer count) = full offload.
        /// Has no effect on the currently loaded model — applies to subsequent loads.
        pub fn with_n_gpu_layers(mut self, n: u32) -> Self {
            self.n_gpu_layers = n;
            self
        }

        /// Configure sampling RNG seed.
        pub fn with_seed(mut self, seed: u32) -> Self {
            self.seed = seed;
            self
        }

        /// Currently configured GPU layer count.
        pub fn n_gpu_layers(&self) -> u32 {
            self.n_gpu_layers
        }

        /// Validate GGUF magic bytes, check memory headroom, then load the
        /// model file into VRAM/RAM.
        pub fn load_model(&mut self, path: &Path) -> Result<(), LlmError> {
            // Verify GGUF magic ("GGUF" as 4 ASCII bytes).
            let mut file = std::fs::File::open(path).map_err(|e| LlmError::ModelLoadFailed {
                reason: format!("open: {e}"),
            })?;
            let mut header = [0u8; 4];
            file.read_exact(&mut header)
                .map_err(|e| LlmError::ModelLoadFailed {
                    reason: format!("read header: {e}"),
                })?;
            if &header != b"GGUF" {
                return Err(LlmError::ModelLoadFailed {
                    reason: format!("not a GGUF file (magic={:?})", header),
                });
            }

            // Memory guard — refuse to attempt the load when the model file
            // alone (×headroom) already exceeds available system memory.
            let file_size = std::fs::metadata(path)
                .map_err(|e| LlmError::ModelLoadFailed {
                    reason: format!("metadata: {e}"),
                })?
                .len();
            let required = (file_size as f64 * MEMORY_HEADROOM_MULT) as u64;
            if let Some(available) = available_memory_bytes() {
                if required > available {
                    return Err(LlmError::InsufficientMemory {
                        required,
                        available,
                    });
                }
            }

            // Drop any previously loaded model before loading a new one.
            // This ensures allocations never overlap (memory-swap safety).
            self.model = None;

            let model_params = LlamaModelParams::default().with_n_gpu_layers(self.n_gpu_layers);
            let model = LlamaModel::load_from_file(&self.backend, path, &model_params).map_err(
                |e| LlmError::ModelLoadFailed {
                    reason: format!("load_from_file: {e}"),
                },
            )?;
            self.model = Some(model);
            Ok(())
        }

        /// Unload the current model, freeing all associated memory before returning.
        pub fn unload_model(&mut self) {
            // Explicit drop before the function returns — required by acceptance criteria.
            drop(self.model.take());
        }

        /// Build the configured sampling chain from generation options.
        fn build_sampler(&self, opts: &GenOpts, top_k: Option<i32>) -> LlamaSampler {
            // Order: top_k → top_p → temp → dist. `chain_simple` builds a
            // standard token sampler with `no_perf=true`.
            let mut samplers: Vec<LlamaSampler> = Vec::with_capacity(4);
            if let Some(k) = top_k {
                if k > 0 {
                    samplers.push(LlamaSampler::top_k(k));
                }
            }
            if opts.top_p > 0.0 && opts.top_p < 1.0 {
                samplers.push(LlamaSampler::top_p(opts.top_p, 1));
            }
            if opts.temperature > 0.0 {
                samplers.push(LlamaSampler::temp(opts.temperature));
                samplers.push(LlamaSampler::dist(self.seed));
            } else {
                // Temperature 0 → deterministic greedy.
                samplers.push(LlamaSampler::greedy());
            }
            LlamaSampler::chain_simple(samplers)
        }

        /// Decode the prompt + stream tokens to the provided callback.
        ///
        /// Each generated token (after detokenisation) is passed to `on_token`.
        /// If the callback returns `Err`, the decode loop exits cleanly.
        fn decode_with<F>(
            &self,
            prompt: &str,
            opts: &GenOpts,
            mut on_token: F,
        ) -> Result<usize, LlmError>
        where
            F: FnMut(String) -> Result<(), LlmError>,
        {
            let model = self.model.as_ref().ok_or_else(|| {
                LlmError::InternalError("no model loaded — call load_model first".into())
            })?;

            let ctx_params = LlamaContextParams::default().with_n_ctx(Some(
                std::num::NonZeroU32::new(self.context_size)
                    .expect("context_size is non-zero at init"),
            ));
            let mut ctx = model
                .new_context(&self.backend, ctx_params)
                .map_err(|e| LlmError::InternalError(format!("new_context: {e}")))?;

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

            // Build the initial batch.
            let mut batch = llama_cpp_2::llama_batch::LlamaBatch::new(512, 1);
            for (i, &tok) in tokens_list.iter().enumerate() {
                let is_last = i == tokens_list.len() - 1;
                batch
                    .add(tok, i as i32, &[0], is_last)
                    .map_err(|e| LlmError::InternalError(format!("batch add: {e}")))?;
            }
            ctx.decode(&mut batch)
                .map_err(|e| LlmError::InternalError(format!("decode: {e}")))?;

            // Configured sampler chain.
            // `top_k` is not in `GenOpts`; default 40 mirrors `GenerateParams::default()`.
            let mut sampler = self.build_sampler(opts, Some(40));

            let mut produced = 0usize;
            let mut so_far = String::new();
            let mut n_cur = batch.n_tokens();

            for _ in 0..opts.max_tokens {
                // Sample at the position of the last decoded token.
                // `sample()` also accepts the token internally (updates sampler state).
                let new_token = sampler.sample(&ctx, batch.n_tokens() - 1);

                if model.is_eog_token(new_token) {
                    break;
                }

                let piece = model
                    .token_to_str(new_token, llama_cpp_2::model::Special::Tokenize)
                    .map_err(|e| LlmError::InternalError(format!("token_to_str: {e}")))?;
                so_far.push_str(&piece);
                produced += 1;
                on_token(piece)?;

                // Stop-sequence check on accumulated detokenised text.
                if opts
                    .stop_sequences
                    .iter()
                    .any(|s| !s.is_empty() && so_far.ends_with(s.as_str()))
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

            Ok(produced)
        }

        /// Stream tokens over a bounded mpsc channel.
        ///
        /// Returns a receiver that yields `Result<String, LlmError>` per token.
        /// The decode loop runs on a blocking thread (llama.cpp inference is
        /// CPU-bound) and the channel closes on completion or error.
        ///
        /// Each emitted item is a detokenised string fragment.
        pub fn generate_stream(
            self: std::sync::Arc<Self>,
            prompt: String,
            opts: GenOpts,
        ) -> mpsc::Receiver<Result<String, LlmError>> {
            let (tx, rx) = mpsc::channel(32);
            tokio::task::spawn_blocking(move || {
                let send_err = |e: LlmError| {
                    let _ = tx.blocking_send(Err(e));
                };
                let res = self.decode_with(&prompt, &opts, |piece| {
                    // If the receiver was dropped, abort the decode loop.
                    tx.blocking_send(Ok(piece)).map_err(|_| {
                        LlmError::InternalError("stream receiver dropped".into())
                    })
                });
                if let Err(e) = res {
                    send_err(e);
                }
                // Channel drops here — receiver sees None and knows we're done.
            });
            rx
        }
    }

    // -------------------------------------------------------------------------
    // LlmBackend impl
    // -------------------------------------------------------------------------

    #[async_trait::async_trait]
    impl LlmBackend for LlamaCpp {
        async fn generate(&self, prompt: &str, opts: GenOpts) -> Result<TokenStream, LlmError> {
            let mut tokens = Vec::with_capacity(opts.max_tokens);
            let produced = self.decode_with(prompt, &opts, |piece| {
                tokens.push(piece);
                Ok(())
            })?;
            let finish_reason = if produced < opts.max_tokens {
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

            let ctx_params = LlamaContextParams::default()
                // SAFETY: 512 is a compile-time non-zero constant.
                .with_n_ctx(Some(std::num::NonZeroU32::new(512).expect("512 is non-zero")))
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
            true
        }

        fn provider(&self) -> &str {
            "llamacpp"
        }
    }

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
