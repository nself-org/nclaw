//! Sync protocol implementation.
//!
//! Modules:
//! - `hlc`: Hybrid Logical Clock for causally-ordered events
//! - `queue`: Offline queue for pending events
//! - `client`: Sync client state machine
//! - `lww`: Last-Write-Wins conflict resolution
//! - `network`: HTTP push/pull/subscribe wrappers
//! - `sign`: Ed25519 event signing and verification
//! - `snapshot`: Device bootstrap snapshot protocol
//! - `heartbeat`: WebSocket keep-alive mechanism
//! - `idempotency`: Duplicate event detection cache
//! - `batching`: Event transmission batching policy
//! - `cursor`: Per-device sync cursor persistence
//! - `upgrade`: Schema version compatibility checking
//! - `telemetry`: Sync metrics collection

pub mod client;
pub mod hlc;
pub mod queue;
pub mod lww;
pub mod network;
pub mod sign;
pub mod snapshot;
pub mod heartbeat;
pub mod idempotency;
pub mod batching;
pub mod cursor;
pub mod upgrade;
pub mod telemetry;

pub use client::{SyncClient, SyncState};
pub use hlc::{Hlc, HlcGenerator};
pub use queue::{OfflineQueue, QueuedEvent};
pub use lww::{EventEnvelope, Op};
pub use network::{SyncNetwork, PushRequest, PullRequest};
pub use sign::{signing_material};
pub use snapshot::{SnapshotRequest, SnapshotResponse};
pub use heartbeat::{HeartbeatTimer, HeartbeatPing};
pub use idempotency::IdempotencyCache;
pub use batching::BatchPolicy;
pub use cursor::Cursor;
pub use upgrade::{CompatStatus, check_compat};
pub use telemetry::{SyncTelemetry, SyncTelemetrySnapshot};
