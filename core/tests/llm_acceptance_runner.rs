//! LLM acceptance runner — CF-01 baseline (P102 S05.T01).
//!
//! Discovers every fixture under `tests/llm_acceptance/fixtures/` and runs it
//! through the deterministic stub backend. Gated behind the
//! `llm-acceptance` feature so it does not run on every `cargo test`.
//!
//! Invocation:
//!   cargo test --features llm-acceptance --test llm_acceptance_runner
//!
//! Output cap and failure shape are designed to be CI-friendly: a single
//! aggregated panic message lists every failed scenario with its reasons,
//! rather than a panic per scenario.

#[path = "llm_acceptance/mod.rs"]
mod llm_acceptance;

#[cfg(feature = "llm-acceptance")]
#[test]
fn runs_all_baseline_fixtures_against_stub() {
    use llm_acceptance::{load_fixtures, run_case, CaseOutcome, StubBackend};
    use std::path::PathBuf;

    let fixtures_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("llm_acceptance")
        .join("fixtures");

    let cases = load_fixtures(&fixtures_dir).expect("load fixtures");
    assert!(
        !cases.is_empty(),
        "no LLM acceptance fixtures found in {} — baseline must include at least one",
        fixtures_dir.display()
    );

    let backend = StubBackend;
    let mut failures: Vec<String> = Vec::new();
    for case in &cases {
        match run_case(&backend, case) {
            CaseOutcome::Pass => {
                eprintln!("PASS  {}", case.name);
            }
            CaseOutcome::Fail { reasons, output } => {
                failures.push(format!(
                    "FAIL  {}\n  reasons:\n    - {}\n  output: {:?}",
                    case.name,
                    reasons.join("\n    - "),
                    output
                ));
            }
            CaseOutcome::BackendError(msg) => {
                failures.push(format!("ERROR {}: backend error: {}", case.name, msg));
            }
        }
    }

    if !failures.is_empty() {
        panic!(
            "LLM acceptance: {} of {} scenarios failed:\n{}",
            failures.len(),
            cases.len(),
            failures.join("\n")
        );
    }
}

// When the feature is off, leave one trivial no-op test so the file always
// compiles into a valid test binary. Prevents `cargo test` from skipping the
// crate entirely and surfacing a confusing 'no tests' state.
#[cfg(not(feature = "llm-acceptance"))]
#[test]
fn llm_acceptance_feature_disabled() {
    eprintln!(
        "llm_acceptance_runner: skipped — enable with --features llm-acceptance"
    );
}
