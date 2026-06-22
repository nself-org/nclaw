//! Deterministic JSON canonicalization per RFC 8785 (JSON Canonicalization Scheme — JCS).
//!
//! Implements byte-stable JSON serialization for cryptographic signing material.
//! The output MUST be byte-identical across runs, processes, languages (Rust ↔ Go),
//! and serde_json::Value backing types. Any reordering would break every signature
//! verified bytewise.
//!
//! Compliance:
//! - Object members sorted by UTF-16 code unit sequence of the member name (RFC 8785 §3.2.3)
//! - No insignificant whitespace (RFC 8785 §3.2.1)
//! - Number serialization per ECMA-262 7.1.12.1 (RFC 8785 §3.2.2.3) — integers as decimal,
//!   floats via shortest round-trip representation (`ryu`-style would be ideal; we delegate to
//!   serde_json's Number which is already ECMA-262 conformant for integers and finite floats)
//! - String escaping per ECMA-262 24.5.2.2 / RFC 8259 §7 (RFC 8785 §3.2.2.2)
//! - Arrays preserve insertion order (RFC 8785 §3.2.4)
//!
//! Companion Go implementation: `plugins-pro/paid/nself-sync/internal/auth/canonical.go`.

use serde_json::Value;
use std::io::Write;

/// Serialize a `serde_json::Value` into RFC 8785-canonical bytes.
///
/// Returns UTF-8 encoded canonical JSON. Output is deterministic across runs.
pub fn canonical_json(value: &Value) -> Vec<u8> {
    let mut out = Vec::with_capacity(64);
    write_value(&mut out, value);
    out
}

fn write_value(out: &mut Vec<u8>, v: &Value) {
    match v {
        Value::Null => {
            out.extend_from_slice(b"null");
        }
        Value::Bool(b) => {
            out.extend_from_slice(if *b { b"true" } else { b"false" });
        }
        Value::Number(n) => {
            write_number(out, n);
        }
        Value::String(s) => {
            write_string(out, s);
        }
        Value::Array(items) => {
            out.push(b'[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(b',');
                }
                write_value(out, item);
            }
            out.push(b']');
        }
        Value::Object(map) => {
            // RFC 8785 §3.2.3: sort by UTF-16 code unit sequence of the member name.
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort_by(|a, b| utf16_codeunit_cmp(a, b));

            out.push(b'{');
            for (i, k) in keys.iter().enumerate() {
                if i > 0 {
                    out.push(b',');
                }
                write_string(out, k);
                out.push(b':');
                // Unwrap is safe: key came from the same map.
                let inner = map.get(*k).expect("key from map");
                write_value(out, inner);
            }
            out.push(b'}');
        }
    }
}

/// Compare two strings by UTF-16 code unit sequence (RFC 8785 §3.2.3 reference algorithm).
///
/// This differs from byte-wise comparison for non-BMP characters and for some
/// characters in the BMP whose UTF-8 byte order differs from UTF-16 code-unit order.
fn utf16_codeunit_cmp(a: &str, b: &str) -> std::cmp::Ordering {
    let mut ai = a.encode_utf16();
    let mut bi = b.encode_utf16();
    loop {
        match (ai.next(), bi.next()) {
            (None, None) => return std::cmp::Ordering::Equal,
            (None, Some(_)) => return std::cmp::Ordering::Less,
            (Some(_), None) => return std::cmp::Ordering::Greater,
            (Some(x), Some(y)) => match x.cmp(&y) {
                std::cmp::Ordering::Equal => continue,
                other => return other,
            },
        }
    }
}

/// Write a string per JCS §3.2.2.2 (ECMA-262 24.5.2.2 / RFC 8259 §7).
///
/// Required escapes: `\"`, `\\`, `\b`, `\f`, `\n`, `\r`, `\t`, plus `\u00XX` for
/// U+0000..U+001F. All other characters (including non-ASCII) emit as UTF-8 verbatim.
fn write_string(out: &mut Vec<u8>, s: &str) {
    out.push(b'"');
    for c in s.chars() {
        match c {
            '"' => out.extend_from_slice(b"\\\""),
            '\\' => out.extend_from_slice(b"\\\\"),
            '\u{08}' => out.extend_from_slice(b"\\b"),
            '\u{0C}' => out.extend_from_slice(b"\\f"),
            '\n' => out.extend_from_slice(b"\\n"),
            '\r' => out.extend_from_slice(b"\\r"),
            '\t' => out.extend_from_slice(b"\\t"),
            c if (c as u32) < 0x20 => {
                // \u00XX hex-lowercase per RFC 8785 §3.2.2.2
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => {
                let mut buf = [0u8; 4];
                let encoded = c.encode_utf8(&mut buf);
                out.extend_from_slice(encoded.as_bytes());
            }
        }
    }
    out.push(b'"');
}

/// Write a number per JCS §3.2.2.3 (ECMA-262 7.1.12.1 ToString).
///
/// serde_json's `Number::Display` impl uses standard Rust formatting which is
/// ECMA-262-conformant for integers (`i64`/`u64`) and is shortest-round-trip
/// conformant for `f64` via Rust's default `{}` formatter (which uses Grisu /
/// shortest-round-trip since Rust 1.55+). Special cases:
///   - serde_json forbids NaN / Infinity in `Number` (it stores them as `Null`
///     via `f64::is_finite` guard at construction), so we don't need to filter.
///   - Integers written without a decimal point.
///   - Negative zero per ECMA-262: "0" (positive). serde_json::Number stores
///     -0.0 as f64; we normalize here.
fn write_number(out: &mut Vec<u8>, n: &serde_json::Number) {
    if let Some(i) = n.as_i64() {
        let _ = write!(out, "{}", i);
        return;
    }
    if let Some(u) = n.as_u64() {
        let _ = write!(out, "{}", u);
        return;
    }
    if let Some(f) = n.as_f64() {
        // Normalize -0.0 to 0.
        if f == 0.0 {
            out.push(b'0');
            return;
        }
        // Integer-valued floats print as integers per ECMA-262 (e.g. 100.0 → "100").
        if f.is_finite() && f.fract() == 0.0 && f.abs() < 1e16 {
            let _ = write!(out, "{}", f as i64);
            return;
        }
        // Fallback to Rust default float formatting (shortest round-trip).
        // Note: ECMA-262 ToString uses similar shortest-round-trip semantics.
        let _ = write!(out, "{}", f);
        return;
    }
    // serde_json::Number always satisfies one of the three branches; this is
    // defensive only.
    let _ = write!(out, "{}", n);
}

// Tests live in `tests/canonical_tests.rs` (uses only public API).
