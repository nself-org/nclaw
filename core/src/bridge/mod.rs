//! Bridge routing engine — decides per-prompt where to send inference.
//!
//! Decision #11: the bridge evaluates each `PromptRequest` against a `BridgeContext`
//! and returns a `RouteDecision` (Local / ServerMux / DirectFrontier / Queue).
//! Pure function, no I/O, no async.
//!
//! S19.T02 adds Transport implementations that execute each RouteDecision.
//! S19.T04-T09 adds budget enforcement, overrides, connection monitoring,
//! privacy filtering, telemetry, and failure policies.

pub mod budget;
pub mod connection;
pub mod failure_policy;
pub mod orchestrator;
pub mod overrides;
pub mod privacy;
pub mod router;
pub mod rule;
pub mod telemetry;
pub mod transport;
