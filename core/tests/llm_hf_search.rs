//! Integration tests for the HuggingFace GGUF model search module (T01).
//!
//! Uses `httpmock` to serve a fake HF API response — no real network calls.
//!
//! Each test uses a unique query string to avoid cache collisions between
//! tests that run concurrently (the module caches results per `(query, limit)`).

use httpmock::prelude::*;
use libnclaw::llm::hf_search::{search_hf, HfSearchParams};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Minimal HuggingFace /models API JSON response with two model entries.
/// The second entry has a sibling GGUF file with a Q4_K_M quant in its name.
const FAKE_HF_RESPONSE: &str = r#"[
  {
    "id": "TheBloke/Llama-2-7B-GGUF",
    "modelId": "TheBloke/Llama-2-7B-GGUF",
    "downloads": 1234567,
    "likes": 8901,
    "tags": ["gguf", "llama"],
    "siblings": [
      { "rfilename": "llama-2-7b-Q4_K_M.gguf", "size": 4081004032 },
      { "rfilename": "llama-2-7b-Q8_0.gguf",   "size": 7161016320 }
    ]
  },
  {
    "id": "TheBloke/Mistral-7B-GGUF",
    "modelId": "TheBloke/Mistral-7B-GGUF",
    "downloads": 654321,
    "likes": 4567,
    "tags": ["gguf", "mistral"],
    "siblings": [
      { "rfilename": "mistral-7b-Q4_K_M.gguf", "size": 4067381248 }
    ]
  }
]"#;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn hf_search_returns_models_from_api() {
    let server = MockServer::start();

    let _mock = server.mock(|when, then| {
        when.method(GET)
            .path("/api/models");
        then.status(200)
            .header("content-type", "application/json")
            .body(FAKE_HF_RESPONSE);
    });

    // Patch the base URL via env var so search_hf hits the mock server.
    // The hf_search module reads HF_API_BASE_URL if set.
    std::env::set_var("HF_API_BASE_URL", server.base_url());

    let params = HfSearchParams {
        query: "llama-gguf-t01-search-unique".into(),
        limit: 20,
    };

    let results = search_hf(params).await.expect("search_hf should succeed");

    assert_eq!(results.len(), 2, "expected two model results");

    let llama = &results[0];
    assert_eq!(llama.id, "TheBloke/Llama-2-7B-GGUF");
    assert_eq!(llama.downloads, 1_234_567);
    assert_eq!(llama.gguf_files.len(), 2, "two GGUF siblings expected");

    // Q4_K_M quant extracted from filename
    let q4 = llama
        .gguf_files
        .iter()
        .find(|f| f.quant.as_deref() == Some("Q4_K_M"))
        .expect("Q4_K_M file not found");
    assert_eq!(q4.quant.as_deref(), Some("Q4_K_M"));
    assert_eq!(q4.size_bytes, Some(4_081_004_032));

    let mistral = &results[1];
    assert_eq!(mistral.id, "TheBloke/Mistral-7B-GGUF");
    assert_eq!(mistral.gguf_files.len(), 1);

    std::env::remove_var("HF_API_BASE_URL");
}

#[tokio::test]
async fn hf_search_returns_empty_on_no_results() {
    let server = MockServer::start();

    let _mock = server.mock(|when, then| {
        when.method(GET).path("/api/models");
        then.status(200)
            .header("content-type", "application/json")
            .body("[]");
    });

    std::env::set_var("HF_API_BASE_URL", server.base_url());

    let results = search_hf(HfSearchParams {
        query: "nonexistent-t01-empty-unique".into(),
        limit: 5,
    })
    .await
    .expect("empty result should not error");

    assert!(results.is_empty(), "expected empty results for blank API response");

    std::env::remove_var("HF_API_BASE_URL");
}

#[tokio::test]
async fn hf_search_propagates_api_error() {
    let server = MockServer::start();

    let _mock = server.mock(|when, then| {
        when.method(GET).path("/api/models");
        then.status(500).body("internal server error");
    });

    std::env::set_var("HF_API_BASE_URL", server.base_url());

    let result = search_hf(HfSearchParams {
        query: "anything-t01-error-unique".into(),
        limit: 5,
    })
    .await;

    assert!(result.is_err(), "HTTP 500 should propagate as error");

    std::env::remove_var("HF_API_BASE_URL");
}
