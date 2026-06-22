//! `NoopMux` and `NoopPlugin` — stub implementations for testing.
//!
//! `NoopMux` returns fixture values without routing; `NoopPlugin` responds to
//! all lifecycle calls without side effects.

use crate::backend::*;
use crate::error::*;
use std::collections::HashMap;
use std::result::Result;

/// Pass-through mux — returns fixture values, no routing.
pub struct NoopMux;

#[async_trait::async_trait]
impl Mux for NoopMux {
    async fn classify(&self, _content: &str) -> Result<Classification, MuxError> {
        Ok(Classification {
            category: "stub".into(),
            confidence: 0.9,
            tags: vec!["test".into()],
        })
    }

    async fn extract_entities(&self, _content: &str) -> Result<Entities, MuxError> {
        Ok(Entities {
            emails: vec!["test@example.com".into()],
            urls: vec!["http://example.com".into()],
            mentions: vec![],
            phone_numbers: vec![],
        })
    }

    async fn route(&self, _content: &str, _context: &str) -> Result<Route, MuxError> {
        Ok(Route {
            handler: "default".into(),
            priority: 1,
            metadata: HashMap::new(),
        })
    }
}

/// Stub plugin — responds to init/execute without side effects.
pub struct NoopPlugin {
    name: String,
}

impl NoopPlugin {
    /// Construct a `NoopPlugin` with the given name.
    pub fn new(name: &str) -> Self {
        NoopPlugin { name: name.into() }
    }
}

#[async_trait::async_trait]
impl Plugin for NoopPlugin {
    fn name(&self) -> &str {
        &self.name
    }

    fn version(&self) -> &str {
        "0.1.0"
    }

    async fn init(&mut self, _config: &PluginConfig) -> Result<(), PluginError> {
        Ok(())
    }

    async fn execute(&self, _capability: &str, input: &Value) -> Result<Value, PluginError> {
        Ok(input.clone())
    }

    async fn shutdown(&self) -> Result<(), PluginError> {
        Ok(())
    }

    async fn health_check(&self) -> Result<(), PluginError> {
        Ok(())
    }
}
