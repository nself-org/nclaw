//! LLM acceptance test harness — CF-01 baseline (P102 S05.T01).
//!
//! Loads acceptance fixtures from `tests/llm_acceptance/fixtures/*.yaml` and
//! runs each scenario through a pluggable backend, asserting that the
//! generated output contains all expected substrings.
//!
//! Design notes:
//! - Decoupled from `libnclaw::backend::LlmBackend` so CI can run against a
//!   deterministic stub without loading a real model. Real-backend acceptance
//!   is layered on later in the CF-01 sprint (S05.T01 platform matrix).
//! - One golden scenario at baseline. The full 20-ticket CF-01 matrix
//!   (5 platforms × T0-T3) expands fixtures incrementally.
//! - Output assertion is structural (substring containment + length bounds),
//!   not exact-match, because LLM output is non-deterministic across versions.
//!
//! Fixture schema (YAML):
//! ```yaml
//! name: string                # unique, kebab-case
//! prompt: string              # input given to the backend
//! model: string               # logical model id (e.g. "qwen2.5-0.5b")
//! expected_substrings: [str]  # ALL must appear in output (case-insensitive)
//! max_tokens: int             # generation cap
//! temperature: float          # 0.0 = deterministic; CI uses 0.0
//! min_output_chars: int       # minimum non-whitespace chars in output
//! ```

use std::collections::HashMap;
use std::fs;
use std::path::Path;

/// One acceptance scenario loaded from a YAML fixture.
///
/// Fields map 1:1 to fixture YAML keys. See module-level docs for schema.
#[derive(Debug, Clone, PartialEq)]
pub struct AcceptanceCase {
    pub name: String,
    pub prompt: String,
    pub model: String,
    pub expected_substrings: Vec<String>,
    pub max_tokens: usize,
    pub temperature: f32,
    pub min_output_chars: usize,
}

/// Pluggable backend trait used by the harness.
///
/// Kept intentionally narrower than `libnclaw::backend::LlmBackend` so a
/// deterministic stub can implement it without depending on the full FFI
/// stack. Real backends (llama.cpp / Ollama / cloud providers) wrap their
/// own adapter that implements this trait in higher-tier CI jobs.
pub trait AcceptanceBackend {
    /// Generate text given a prompt + case config. Must be deterministic when
    /// `case.temperature == 0.0` so CI snapshots are reproducible.
    fn generate(&self, case: &AcceptanceCase) -> Result<String, String>;
}

/// Outcome of running one scenario.
#[derive(Debug, Clone, PartialEq)]
pub enum CaseOutcome {
    Pass,
    /// Output failed at least one assertion. `reasons` lists every failure
    /// (not just the first) so CI logs explain all gaps at once.
    Fail { reasons: Vec<String>, output: String },
    /// Backend returned an error before any assertion could run.
    BackendError(String),
}

/// Load every `*.yaml` fixture from `dir` into `AcceptanceCase` values.
///
/// Returns fixtures in filename-sorted order so test output is stable.
/// Uses a minimal hand-rolled YAML parser (only the subset our schema needs)
/// to avoid pulling a YAML dep into `[dev-dependencies]` for this baseline.
pub fn load_fixtures(dir: &Path) -> Result<Vec<AcceptanceCase>, String> {
    let mut entries: Vec<_> = fs::read_dir(dir)
        .map_err(|e| format!("read_dir({}): {}", dir.display(), e))?
        .filter_map(|r| r.ok())
        .filter(|e| {
            e.path()
                .extension()
                .and_then(|s| s.to_str())
                .map(|s| s == "yaml" || s == "yml")
                .unwrap_or(false)
        })
        .collect();
    entries.sort_by_key(|e| e.path());

    let mut out = Vec::with_capacity(entries.len());
    for entry in entries {
        let path = entry.path();
        let text = fs::read_to_string(&path)
            .map_err(|e| format!("read {}: {}", path.display(), e))?;
        let case = parse_fixture(&text)
            .map_err(|e| format!("parse {}: {}", path.display(), e))?;
        out.push(case);
    }
    Ok(out)
}

/// Run one scenario through a backend and check assertions.
///
/// Assertions:
/// 1. Output length >= `case.min_output_chars` (non-whitespace).
/// 2. Every entry in `case.expected_substrings` appears in output
///    (case-insensitive — LLMs may capitalize inconsistently).
pub fn run_case<B: AcceptanceBackend>(backend: &B, case: &AcceptanceCase) -> CaseOutcome {
    let output = match backend.generate(case) {
        Ok(s) => s,
        Err(e) => return CaseOutcome::BackendError(e),
    };

    let mut reasons = Vec::new();
    let nonws_len = output.chars().filter(|c| !c.is_whitespace()).count();
    if nonws_len < case.min_output_chars {
        reasons.push(format!(
            "output length {} chars < min_output_chars {}",
            nonws_len, case.min_output_chars
        ));
    }

    let lower = output.to_lowercase();
    for needle in &case.expected_substrings {
        if !lower.contains(&needle.to_lowercase()) {
            reasons.push(format!("missing expected substring: {:?}", needle));
        }
    }

    if reasons.is_empty() {
        CaseOutcome::Pass
    } else {
        CaseOutcome::Fail { reasons, output }
    }
}

// ---------------------------------------------------------------------------
// Minimal YAML parser for the fixture schema.
//
// Supports exactly what the schema needs:
//   - top-level `key: value` pairs (strings, ints, floats)
//   - `key:` followed by `- item` lines for string lists
//   - `#` line comments
//   - quoted or unquoted string scalars
// Anything beyond this surface returns an error rather than guessing.
// ---------------------------------------------------------------------------

fn parse_fixture(text: &str) -> Result<AcceptanceCase, String> {
    let mut scalars: HashMap<String, String> = HashMap::new();
    let mut lists: HashMap<String, Vec<String>> = HashMap::new();
    let mut current_list: Option<String> = None;

    for (lineno, raw_line) in text.lines().enumerate() {
        let line = strip_comment(raw_line);
        if line.trim().is_empty() {
            continue;
        }
        // List item line: "  - value"
        if let Some(rest) = line.trim_start().strip_prefix("- ") {
            let key = current_list.as_ref().ok_or_else(|| {
                format!("line {}: list item without parent key", lineno + 1)
            })?;
            lists
                .entry(key.clone())
                .or_default()
                .push(unquote(rest.trim()));
            continue;
        }
        // key: value or key: (list follows)
        let (k, v) = match line.split_once(':') {
            Some((k, v)) => (k.trim().to_string(), v.trim().to_string()),
            None => {
                return Err(format!("line {}: not a key:value pair: {:?}", lineno + 1, line));
            }
        };
        if v.is_empty() {
            current_list = Some(k);
        } else {
            current_list = None;
            scalars.insert(k, unquote(&v));
        }
    }

    let get = |key: &str| -> Result<&String, String> {
        scalars
            .get(key)
            .ok_or_else(|| format!("missing required key: {}", key))
    };
    let get_usize = |key: &str| -> Result<usize, String> {
        get(key)?
            .parse::<usize>()
            .map_err(|e| format!("{}: not a usize: {}", key, e))
    };
    let get_f32 = |key: &str| -> Result<f32, String> {
        get(key)?
            .parse::<f32>()
            .map_err(|e| format!("{}: not an f32: {}", key, e))
    };

    Ok(AcceptanceCase {
        name: get("name")?.clone(),
        prompt: get("prompt")?.clone(),
        model: get("model")?.clone(),
        expected_substrings: lists
            .get("expected_substrings")
            .cloned()
            .unwrap_or_default(),
        max_tokens: get_usize("max_tokens")?,
        temperature: get_f32("temperature")?,
        min_output_chars: get_usize("min_output_chars")?,
    })
}

fn strip_comment(line: &str) -> &str {
    // Naive: respects '#' only when outside a quoted string. Schema only uses
    // '#' for end-of-line comments, so this is safe.
    let mut in_q = false;
    let mut quote_ch = ' ';
    for (i, c) in line.char_indices() {
        match c {
            '"' | '\'' if !in_q => {
                in_q = true;
                quote_ch = c;
            }
            c if in_q && c == quote_ch => in_q = false,
            '#' if !in_q => return &line[..i],
            _ => {}
        }
    }
    line
}

fn unquote(s: &str) -> String {
    let t = s.trim();
    if (t.starts_with('"') && t.ends_with('"') && t.len() >= 2)
        || (t.starts_with('\'') && t.ends_with('\'') && t.len() >= 2)
    {
        t[1..t.len() - 1].to_string()
    } else {
        t.to_string()
    }
}

// ---------------------------------------------------------------------------
// Deterministic stub backend.
//
// Used by the baseline CI workflow so PR runs are repeatable without a real
// model artifact. Recognises a small canned-prompt table; returns a clearly
// labelled fallback for unknown prompts so test failures point at the gap.
// ---------------------------------------------------------------------------

/// A deterministic, model-free backend that emits canned responses for the
/// baseline acceptance fixtures. Real backends replace this in higher CI tiers.
pub struct StubBackend;

impl AcceptanceBackend for StubBackend {
    fn generate(&self, case: &AcceptanceCase) -> Result<String, String> {
        // Canned table — extend in lockstep with fixture additions.
        // Keyed on the case name (stable, kebab-case) rather than prompt text,
        // so prompt edits don't silently divert to the unknown-prompt fallback.
        let body = match case.name.as_str() {
            "summarize-paragraph-baseline" => {
                "The paragraph describes a cat that climbed a tree, watched birds, \
                 and eventually came down when called. Summary: a curious cat \
                 explored a tree."
            }
            // CF-01 T02: code-completion. Returns the canonical body for the
            // prompt `fn add(a, b) -> i32`. Substring match covers `a + b`.
            "code-completion" => {
                "    a + b\n}"
            }
            // CF-01 T03: question-answering. Single-noun factual answer.
            "qa" => {
                "The capital of France is Paris."
            }
            // CF-01 T04: longer summarization. Two-sentence collapse with the
            // central noun ("garden") preserved.
            "summarize-long" => {
                "Maria built a thriving backyard garden of tomatoes, basil, and \
                 peppers each spring. The garden became her weekly refuge and a \
                 source of produce she shared with neighbors."
            }
            // CF-01 T05: instruction-following / formatted output. Emits a JSON
            // array of three fruit names — the harness only checks structural
            // substrings, deep JSON validity lives in json_mode_validity.rs.
            "instruction-following" => {
                "[\"apple\", \"banana\", \"cherry\"]"
            }
            _ => {
                return Err(format!(
                    "StubBackend: no canned response for case {:?} (add one in \
                     tests/llm_acceptance/mod.rs when you add a fixture)",
                    case.name
                ));
            }
        };
        // Respect max_tokens loosely by char-truncating, so the assertion path
        // exercises both the substring check and the length check.
        let cap = case.max_tokens.saturating_mul(8);
        if body.len() > cap {
            Ok(body.chars().take(cap).collect())
        } else {
            Ok(body.to_string())
        }
    }
}

#[cfg(test)]
mod self_tests {
    use super::*;

    #[test]
    fn parse_minimal_fixture() {
        let yaml = r#"
name: summarize-paragraph-baseline
prompt: "Summarize: a cat climbed a tree."
model: stub-v0
max_tokens: 64
temperature: 0.0
min_output_chars: 20
expected_substrings:
  - cat
  - tree
"#;
        let case = parse_fixture(yaml).expect("parse ok");
        assert_eq!(case.name, "summarize-paragraph-baseline");
        assert_eq!(case.expected_substrings, vec!["cat", "tree"]);
        assert_eq!(case.max_tokens, 64);
        assert!((case.temperature - 0.0).abs() < f32::EPSILON);
    }

    #[test]
    fn stub_backend_pass_on_baseline_case() {
        let case = AcceptanceCase {
            name: "summarize-paragraph-baseline".into(),
            prompt: "irrelevant".into(),
            model: "stub-v0".into(),
            expected_substrings: vec!["cat".into(), "tree".into()],
            max_tokens: 64,
            temperature: 0.0,
            min_output_chars: 20,
        };
        let outcome = run_case(&StubBackend, &case);
        assert_eq!(outcome, CaseOutcome::Pass);
    }

    #[test]
    fn stub_backend_fail_reports_all_reasons() {
        let case = AcceptanceCase {
            name: "summarize-paragraph-baseline".into(),
            prompt: "irrelevant".into(),
            model: "stub-v0".into(),
            expected_substrings: vec!["DEFINITELY-MISSING".into(), "ALSO-MISSING".into()],
            max_tokens: 64,
            temperature: 0.0,
            min_output_chars: 100_000,
        };
        match run_case(&StubBackend, &case) {
            CaseOutcome::Fail { reasons, .. } => {
                assert!(reasons.iter().any(|r| r.contains("min_output_chars")));
                assert_eq!(
                    reasons.iter().filter(|r| r.contains("missing expected")).count(),
                    2
                );
            }
            other => panic!("expected Fail, got {:?}", other),
        }
    }

    #[test]
    fn stub_backend_errors_on_unknown_case() {
        let case = AcceptanceCase {
            name: "unknown-scenario".into(),
            prompt: "x".into(),
            model: "stub-v0".into(),
            expected_substrings: vec![],
            max_tokens: 64,
            temperature: 0.0,
            min_output_chars: 1,
        };
        match run_case(&StubBackend, &case) {
            CaseOutcome::BackendError(msg) => assert!(msg.contains("unknown-scenario")),
            other => panic!("expected BackendError, got {:?}", other),
        }
    }
}
