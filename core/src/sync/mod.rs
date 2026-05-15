//! Sync protocol implementation.
//!
//! Modules:
//! - `hlc`: Hybrid Logical Clock for causally-ordered events
//! - `queue`: Offline queue for pending events
//! - `client`: Sync client state machine
//! - `lww`: Last-Write-Wins conflict resolution
//! - `network`: HTTP push/pull/subscribe wrappers
//! - `retry`: Bounded retry policy with exponential backoff + full jitter
//! - `canonical`: RFC 8785 JSON canonicalization for signing material (V04-F03)
//! - `sign`: Ed25519 event signing and verification
//! - `snapshot`: Device bootstrap snapshot protocol
//! - `heartbeat`: WebSocket keep-alive mechanism
//! - `idempotency`: Duplicate event detection cache
//! - `batching`: Event transmission batching policy
//! - `cursor`: Per-device sync cursor persistence
//! - `upgrade`: Schema version compatibility checking
//! - `telemetry`: Sync metrics collection

pub mod batching;
pub mod canonical;
pub mod client;
pub mod cursor;
pub mod heartbeat;
pub mod hlc;
pub mod idempotency;
pub mod lww;
pub mod network;
pub mod queue;
pub mod retry;
pub mod sign;
pub mod snapshot;
pub mod telemetry;
pub mod upgrade;

pub use batching::BatchPolicy;
pub use client::{SyncClient, SyncState};
pub use cursor::Cursor;
pub use heartbeat::{HeartbeatPing, HeartbeatTimer};
pub use hlc::{Hlc, HlcGenerator};
pub use idempotency::IdempotencyCache;
pub use lww::{EventEnvelope, Op};
pub use network::{
    AckRequest, AuthFrame, EventAck, PullRequest, PullResponse, PushCursor, PushRequest,
    PushResponse, PushResult, SyncNetwork,
};
pub use queue::{OfflineQueue, QueuedEvent};
pub use retry::{is_retryable_status, parse_retry_after, RetryDecision, RetryPolicy};
pub use sign::signing_material;
pub use snapshot::{SnapshotRequest, SnapshotResponse};
pub use telemetry::{SyncTelemetry, SyncTelemetrySnapshot};
pub use upgrade::{check_compat, CompatStatus};
