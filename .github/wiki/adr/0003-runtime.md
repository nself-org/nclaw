# ADR-0003: Runtime Architecture (Rust + Tokio)

**Status:** Accepted 2026-05-11  
**Context:** Core logic must run safely across desktop, mobile, and async contexts.  
**Decision:** Implement core in Rust with tokio async runtime and structured logging.  

## Context

Business logic (sync engine, encryption, LLM orchestration, credential management) must be memory-safe, perform well, and integrate cleanly with both desktop (Tauri + React) and mobile (Flutter) frontends.

## Decision

Core runtime is Rust (`nclaw-core` crate) with:
- **tokio** for async/await and multi-threaded execution
- **tracing** for structured observability and logging
- Standard library for security primitives (randomness, constant-time comparisons)

## Rationale

- **Memory safety:** Rust eliminates whole classes of bugs (use-after-free, buffer overflows, data races).
- **Async-first design:** tokio handles sync engine subscriptions, network I/O, and LLM calls without blocking.
- **Observability:** tracing integrates with server-side metrics; structured logs are queryable.
- **Type safety:** Rust's type system catches FFI boundary errors at compile time.

## Consequences

**Positive:**
- No memory leaks, no runtime panics from unsafe casts.
- Both Tauri and Flutter can safely call async Rust functions.

**Negative:**
- Rust compile times are longer than Go or Python.
- Learning curve for team members unfamiliar with Rust.

## Alternatives Considered

- **Go:** Simpler FFI, faster build, but less memory safety for pointer-heavy code (encryption keys, credential buffers).
- **C/C++:** Maximum performance, but manual memory management is error-prone.

## References

- Tokio: https://tokio.rs/  
- Tracing: https://docs.rs/tracing/  
- Rust FFI: https://doc.rust-lang.org/nomicon/ffi.html
