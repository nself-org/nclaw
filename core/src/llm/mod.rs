//! LLM backend abstractions and feature-gated implementations.

pub mod backend;
pub mod constraint;
pub mod context;
pub mod dampers;
pub mod roles;
pub mod sampling;
pub mod stream;

pub use constraint::{parse_tool_call, GenerationConstraint, Grammars, ToolCall};
pub use dampers::{
    apply_low_power_damper, local_llm_disabled_by_battery, thermal_inter_token_delay_ms,
    DamperState, ThermalLevel,
};
pub use roles::{ModelRoles, RolesConfig};
