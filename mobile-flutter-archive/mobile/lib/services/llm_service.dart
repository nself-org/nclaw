/// LlmService wraps Rust core local LLM FFI.
///
/// Migrates from MethodChannel (native iOS/Android) to Rust core.
/// Stub: FFI calls wired on first `make codegen` run + S15.T18 mobile FFI integration.
class LlmService {
  /// Initialize local LLM (llama.cpp or ollama backend via Rust).
  ///
  /// Calls Rust: nclaw_init_llm(model_path, config)
  Future<void> initialize({
    required String modelPath,
    required Map<String, dynamic> config,
  }) async {
    // Stub: FFI call pending codegen
    // await api.initLlm(modelPath: modelPath, config: config);
  }

  /// Generate text completion from prompt.
  ///
  /// Calls Rust: nclaw_llm_infer(prompt, max_tokens)
  Future<String> infer(String prompt, {int maxTokens = 256}) async {
    // Stub: FFI call pending codegen
    // return await api.llmInfer(prompt: prompt, maxTokens: maxTokens);
    return '';
  }

  /// Embed text to vector via local LLM.
  ///
  /// Calls Rust: nclaw_llm_embed(text) → returns embedding vector
  Future<List<double>> embed(String text) async {
    // Stub: FFI call pending codegen
    // return await api.llmEmbed(text: text);
    return [];
  }

  /// Check if LLM is loaded and ready.
  Future<bool> isReady() async {
    // Stub: FFI call pending codegen
    // return await api.llmIsReady();
    return false;
  }

  /// Unload LLM to free memory.
  Future<void> unload() async {
    // Stub: FFI call pending codegen
    // await api.llmUnload();
  }
}
