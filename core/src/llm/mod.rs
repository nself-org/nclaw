//! LLM backend abstractions and feature-gated implementations.

pub mod backend;
pub mod constraint;
pub mod context;
pub mod dampers;
pub mod roles;
pub mod sampling;
pub mod stream;

pub use constraint::{GenerationConstraint, Grammars, ToolCall, parse_tool_call};
pub use dampers::{DamperState, ThermalLevel, apply_low_power_damper, local_llm_disabled_by_battery, thermal_inter_token_delay_ms};
pub use roles::{ModelRoles, RolesConfig};
