//! llama.cpp FFI wrapper (feature-gated).
//!
//! The full `LlmBackend` trait implementation lands in T02.
//! This module provides the struct scaffold so T02 has a home to impl into.

#[cfg(feature = "cpu")]
pub struct LlamaCpp {
    _placeholder: (),
}

#[cfg(feature = "cpu")]
impl LlamaCpp {
    pub fn new() -> Result<Self, crate::error::LlmError> {
        Ok(Self { _placeholder: () })
    }
}

#[cfg(feature = "metal")]
pub struct LlamaCppMetal {
    _placeholder: (),
}

#[cfg(feature = "metal")]
impl LlamaCppMetal {
    pub fn new() -> Result<Self, crate::error::LlmError> {
        Ok(Self { _placeholder: () })
    }
}
