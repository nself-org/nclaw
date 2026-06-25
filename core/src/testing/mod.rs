//! Mock backends for testing — in-memory implementations of all major traits.
//!
//! Provides typed builders: `InMemoryDb::builder()`, `InMemoryLlm::builder()`,
//! `InMemorySync::builder()`, `InMemoryVault::builder()`, plus `NoopMux` and
//! `NoopPlugin`.
//!
//! Use in integration tests to verify client behavior without live backends.
//!
//! # Submodules
//!
//! - `sync` — `InMemorySync` builder and trait impl
//! - `vault` — `InMemoryVault` builder and trait impl
//! - `plugins` — `NoopMux` and `NoopPlugin` trait impls

pub mod plugins;
pub mod sync;
pub mod vault;

pub use plugins::{NoopMux, NoopPlugin};
pub use sync::{InMemorySync, InMemorySyncBuilder};
pub use vault::{InMemoryVault, InMemoryVaultBuilder};

use crate::backend::*;
use crate::error::*;
use std::collections::HashMap;
use std::result::Result;
use std::sync::{Arc, Mutex};

// ============================================================================
// InMemoryDb
// ============================================================================

/// In-memory database — Vec<Row> store, no persistence, supports basic queries.
pub struct InMemoryDb {
    data: Arc<Mutex<Vec<Row>>>,
}

impl InMemoryDb {
    /// Create a builder for constructing an `InMemoryDb` with pre-loaded rows.
    pub fn builder() -> InMemoryDbBuilder {
        InMemoryDbBuilder { rows: Vec::new() }
    }
}

/// Builder for `InMemoryDb` — pre-seed rows before building.
pub struct InMemoryDbBuilder {
    rows: Vec<Row>,
}

impl InMemoryDbBuilder {
    /// Pre-load the database with the given rows (replaces any previously set rows).
    pub fn with_data(mut self, rows: Vec<Row>) -> Self {
        self.rows = rows;
        self
    }

    /// Build the `InMemoryDb`, moving pre-loaded rows into the shared state.
    pub fn build(self) -> InMemoryDb {
        InMemoryDb {
            data: Arc::new(Mutex::new(self.rows)),
        }
    }
}

#[async_trait::async_trait]
impl Database for InMemoryDb {
    async fn execute(&self, _sql: &str, _params: &[Value]) -> Result<u64, DbError> {
        let mut data = self.data.lock().unwrap();
        let count = data.len() as u64;
        // Stub: simulate INSERT
        data.push(HashMap::new());
        Ok(count + 1)
    }

    async fn query(&self, _sql: &str, _params: &[Value]) -> Result<Vec<Row>, DbError> {
        let data = self.data.lock().unwrap();
        Ok(data.clone())
    }

    async fn migrate(&self, _version: u32) -> Result<(), DbError> {
        Ok(())
    }

    async fn health_check(&self) -> Result<(), DbError> {
        Ok(())
    }
}

// ============================================================================
// InMemoryLlm
// ============================================================================

/// Mock LLM backend — returns canned token streams from fixture map.
pub struct InMemoryLlm {
    fixtures: Arc<Mutex<HashMap<String, Vec<String>>>>,
}

impl InMemoryLlm {
    /// Create a builder for constructing an `InMemoryLlm` with canned response fixtures.
    pub fn builder() -> InMemoryLlmBuilder {
        InMemoryLlmBuilder {
            fixtures: HashMap::new(),
        }
    }
}

/// Builder for `InMemoryLlm` — map prompt strings to expected token sequences.
pub struct InMemoryLlmBuilder {
    fixtures: HashMap<String, Vec<String>>,
}

impl InMemoryLlmBuilder {
    /// Register a canned response: when `prompt` is seen, return `tokens`.
    pub fn with_fixture(mut self, prompt: String, tokens: Vec<String>) -> Self {
        self.fixtures.insert(prompt, tokens);
        self
    }

    /// Build the `InMemoryLlm` with all registered fixtures.
    pub fn build(self) -> InMemoryLlm {
        InMemoryLlm {
            fixtures: Arc::new(Mutex::new(self.fixtures)),
        }
    }
}

#[async_trait::async_trait]
impl LlmBackend for InMemoryLlm {
    async fn generate(&self, prompt: &str, _opts: GenOpts) -> Result<TokenStream, LlmError> {
        let fixtures = self.fixtures.lock().unwrap();
        let tokens = fixtures
            .get(prompt)
            .cloned()
            .unwrap_or_else(|| vec!["[stub-response]".into()]);
        Ok(TokenStream {
            tokens,
            finish_reason: "stop".into(),
        })
    }

    async fn embed(&self, _text: &str) -> Result<Vec<f32>, LlmError> {
        Ok(vec![0.1, 0.2, 0.3, 0.4])
    }

    fn supports_streaming(&self) -> bool {
        true
    }

    fn provider(&self) -> &str {
        "mock"
    }
}

// Tests live in `tests/testing_mocks_test.rs` (uses only public API).
