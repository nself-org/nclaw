//! Bridge routing engine — decides per-prompt where to send inference.
//!
//! Decision #11: the bridge evaluates each `PromptRequest` against a `BridgeContext`
//! and returns a `RouteDecision` (Local / ServerMux / DirectFrontier / Queue).
//! Pure function, no I/O, no async.

pub mod router;
pub mod rule;
