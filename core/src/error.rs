//! Error types for libnclaw core
//!
//! Comprehensive error hierarchy using `thiserror` for ergonomic error handling and
//! automatic error chain propagation. Each subsystem (LLM, DB, Sync, etc.) defines
//! its own error variants.

use thiserror::Error;

pub type Result<T> = std::result::Result<T, CoreError>;

/// Top-level error type for all libnclaw core operations.
#[derive(Error, Debug)]
pub enum CoreError {
    #[error("LLM error: {0}")]
    Llm(#[from] LlmError),

    #[error("Database error: {0}")]
    Db(#[from] DbError),

    #[error("Sync error: {0}")]
    Sync(#[from] SyncError),

    #[error("Vault error: {0}")]
    Vault(#[from] VaultError),

    #[error("Mux error: {0}")]
    Mux(#[from] MuxError),

    #[error("Transport error: {0}")]
    Transport(#[from] TransportError),

    #[error("Config error: {0}")]
    Config(#[from] ConfigError),

    #[error("Crypto error: {0}")]
    Crypto(#[from] CryptoError),

    #[error("Plugin error: {0}")]
    Plugin(#[from] PluginError),

    #[error("{0}")]
    Other(String),

    #[error("not implemented: {0}")]
    NotImplemented(String),

    #[error("serialization error: {0}")]
    Serialization(String),
}

impl From<serde_json::Error> for CoreError {
    fn from(e: serde_json::Error) -> Self {
        CoreError::Serialization(e.to_string())
    }
}

/// LLM backend errors: provider connectivity, model issues, token limits.
#[derive(Error, Debug)]
pub enum LlmError {
    #[error("Provider unreachable: {0}")]
    ProviderUnreachable(String),

    #[error("Model not found: {0}")]
    ModelNotFound(String),

    #[error("Token limit exceeded: {requested} > {limit}")]
    TokenLimitExceeded { requested: usize, limit: usize },

    #[error("Invalid response: {0}")]
    InvalidResponse(String),

    #[error("Rate limited")]
    RateLimited,

    #[error("Internal error: {0}")]
    InternalError(String),

    #[error("Insufficient memory to load model: required {required} bytes, available {available} bytes")]
    InsufficientMemory { required: u64, available: u64 },

    #[error("Model load failed: {reason}")]
    ModelLoadFailed { reason: String },
}

/// Database errors: connection, query, schema mismatches.
#[derive(Error, Debug)]
pub enum DbError {
    #[error("Connection failed: {0}")]
    ConnectionFailed(String),

    #[error("Query failed: {0}")]
    QueryFailed(String),

    #[error("Row not found")]
    RowNotFound,

    #[error("Transaction failed: {0}")]
    TransactionFailed(String),

    #[error("Schema mismatch: {0}")]
    SchemaMismatch(String),

    #[error("Constraint violated: {0}")]
    ConstraintViolation(String),

    #[error("Decryption failed: wrong key or corrupt database")]
    DbDecryptionFailed,
}

/// Sync errors: state drift, version mismatch, merge conflicts.
#[derive(Error, Debug)]
pub enum SyncError {
    #[error("Version mismatch: local={local}, remote={remote}")]
    VersionMismatch { local: u64, remote: u64 },

    #[error("State drift detected")]
    StateDrift,

    #[error("Merge conflict: {0}")]
    MergeConflict(String),

    #[error("Sync timeout")]
    Timeout,

    #[error("Invalid state: {0}")]
    InvalidState(String),
}

/// Vault errors: key derivation, secret storage, encryption.
#[derive(Error, Debug)]
pub enum VaultError {
    #[error("Key derivation failed")]
    KeyDerivationFailed,

    #[error("Secret not found: {0}")]
    SecretNotFound(String),

    #[error("Invalid format")]
    InvalidFormat,

    #[error("Encryption failed: {0}")]
    EncryptionFailed(String),

    #[error("Decryption failed: {0}")]
    DecryptionFailed(String),
}

/// Mux errors: routing, classification, message handling.
#[derive(Error, Debug)]
pub enum MuxError {
    #[error("No route for: {0}")]
    NoRoute(String),

    #[error("Classification failed: {0}")]
    ClassificationFailed(String),

    #[error("Invalid message format")]
    InvalidMessageFormat,

    #[error("Multiplexing failed: {0}")]
    MultiplexingFailed(String),
}

/// Transport errors: network, serialization, protocol.
#[derive(Error, Debug)]
pub enum TransportError {
    #[error("Network error: {0}")]
    Network(String),

    #[error("Serialization failed: {0}")]
    SerializationFailed(String),

    #[error("Deserialization failed: {0}")]
    DeserializationFailed(String),

    #[error("Protocol violation: {0}")]
    ProtocolViolation(String),

    #[error("Invalid URL: {0}")]
    InvalidUrl(String),

    /// All retry attempts for a transient transport failure were exhausted.
    /// `attempts` is the total number of tries (initial + retries); `last_status`
    /// is the most recent HTTP status code observed (or `0` for non-HTTP
    /// failures such as connect/timeout). `last_message` carries the trailing
    /// error string for diagnostics.
    #[error("retry exhausted after {attempts} attempts (last_status={last_status}): {last_message}")]
    RetryExhausted {
        attempts: u32,
        last_status: u16,
        last_message: String,
    },
}

/// Config errors: missing, invalid, or incompatible settings.
#[derive(Error, Debug)]
pub enum ConfigError {
    #[error("Missing: {0}")]
    MissingRequired(String),

    #[error("Invalid value: {0}")]
    InvalidValue(String),

    #[error("Parse error: {0}")]
    ParseError(String),

    #[error("Incompatible: {0}")]
    Incompatible(String),
}

/// Crypto errors: key generation, AEAD, signatures.
#[derive(Error, Debug)]
pub enum CryptoError {
    #[error("Invalid key: {0}")]
    InvalidKey(String),

    #[error("AEAD seal failed")]
    SealFailed,

    #[error("AEAD open failed")]
    OpenFailed,

    #[error("Signature invalid")]
    SignatureInvalid,

    #[error("Base64 error: {0}")]
    Base64Error(String),

    #[error("Random failed: {0}")]
    RandomFailed(String),
}

/// Plugin errors: not found, incompatible, signature issues.
#[derive(Error, Debug)]
pub enum PluginError {
    #[error("Plugin not found: {0}")]
    NotFound(String),

    #[error("Incompatible: {0}")]
    Incompatible(String),

    #[error("Signature mismatch")]
    SignatureMismatch,

    #[error("Init failed: {0}")]
    InitializationFailed(String),

    #[error("Exec failed: {0}")]
    ExecutionFailed(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_llm_error_chain() {
        let err = LlmError::ModelNotFound("gpt-5".into());
        let core: CoreError = err.into();
        assert!(core.to_string().contains("LLM error"));
    }

    #[test]
    fn test_db_error_chain() {
        let err = DbError::RowNotFound;
        let core: CoreError = err.into();
        assert_eq!(core.to_string(), "Database error: Row not found");
    }

    #[test]
    fn test_all_errors_propagate() {
        let _: CoreError = LlmError::RateLimited.into();
        let _: CoreError = DbError::ConnectionFailed("timeout".into()).into();
        let _: CoreError = SyncError::Timeout.into();
        let _: CoreError = CryptoError::OpenFailed.into();
    }
}
