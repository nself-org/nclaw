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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn primitives() {
        assert_eq!(canonical_json(&Value::Null), b"null");
        assert_eq!(canonical_json(&Value::Bool(true)), b"true");
        assert_eq!(canonical_json(&Value::Bool(false)), b"false");
        assert_eq!(canonical_json(&json!(42)), b"42");
        assert_eq!(canonical_json(&json!(-7)), b"-7");
        assert_eq!(canonical_json(&json!(0)), b"0");
        assert_eq!(canonical_json(&json!("")), b"\"\"");
    }

    #[test]
    fn negative_zero_normalizes_to_zero() {
        let v: Value = serde_json::from_str("-0.0").unwrap();
        assert_eq!(canonical_json(&v), b"0");
    }

    #[test]
    fn integer_valued_float_prints_as_int() {
        let v: Value = serde_json::from_str("100.0").unwrap();
        assert_eq!(canonical_json(&v), b"100");
    }

    #[test]
    fn object_keys_sorted_utf16() {
        let v = json!({"c": 1, "a": 2, "b": 3});
        assert_eq!(canonical_json(&v), br#"{"a":2,"b":3,"c":1}"#);
    }

    #[test]
    fn object_key_reorder_produces_same_output() {
        let v1 = json!({"z": 1, "a": 2, "m": 3});
        let v2 = json!({"a": 2, "m": 3, "z": 1});
        let v3 = json!({"m": 3, "z": 1, "a": 2});
        let c1 = canonical_json(&v1);
        let c2 = canonical_json(&v2);
        let c3 = canonical_json(&v3);
        assert_eq!(c1, c2);
        assert_eq!(c2, c3);
        assert_eq!(c1, br#"{"a":2,"m":3,"z":1}"#);
    }

    #[test]
    fn nested_objects_sorted_recursively() {
        let v = json!({
            "outer_b": {"y": 1, "x": 2},
            "outer_a": {"d": 1, "c": 2}
        });
        let canon = canonical_json(&v);
        assert_eq!(
            std::str::from_utf8(&canon).unwrap(),
            r#"{"outer_a":{"c":2,"d":1},"outer_b":{"x":2,"y":1}}"#
        );
    }

    #[test]
    fn arrays_preserve_order() {
        let v = json!([3, 1, 2, "z", "a"]);
        assert_eq!(canonical_json(&v), br#"[3,1,2,"z","a"]"#);
    }

    #[test]
    fn empty_object_and_array() {
        assert_eq!(canonical_json(&json!({})), b"{}");
        assert_eq!(canonical_json(&json!([])), b"[]");
    }

    #[test]
    fn string_escapes() {
        let v = json!("a\"b\\c\nd\re\tf\u{0008}g\u{000c}h");
        let canon = canonical_json(&v);
        // \" \\ \n \r \t \b \f all required two-char escapes.
        assert_eq!(canon, br#""a\"b\\c\nd\re\tf\bg\fh""#);
    }

    #[test]
    fn control_char_hex_escape() {
        let v = json!("\u{0001}\u{001f}");
        // fix: stale test — RFC 8785 §3.1.4 mandates control chars escape as \u00XX lowercase hex.
        assert_eq!(canonical_json(&v), br#""\u0001\u001f""#);
    }

    #[test]
    fn unicode_passthrough_no_escape() {
        // U+00E9 (é) and U+4E2D (中) emit as UTF-8 bytes verbatim.
        let v = json!("é中");
        let canon = canonical_json(&v);
        // "é中" = "\"" + 0xC3 0xA9 + 0xE4 0xB8 0xAD + "\""
        assert_eq!(canon, &[b'"', 0xC3, 0xA9, 0xE4, 0xB8, 0xAD, b'"'][..]);
    }

    #[test]
    fn deeply_nested_golden_fixture() {
        // Build the same object two ways with key reordering and verify identical output.
        let v1 = json!({
            "z_field": [1, 2, {"nested_b": "v", "nested_a": "u"}],
            "a_field": {"deep": {"c": 3, "a": 1, "b": 2}},
            "m_field": null
        });
        let v2 = json!({
            "a_field": {"deep": {"b": 2, "c": 3, "a": 1}},
            "m_field": null,
            "z_field": [1, 2, {"nested_a": "u", "nested_b": "v"}]
        });
        let c1 = canonical_json(&v1);
        let c2 = canonical_json(&v2);
        assert_eq!(c1, c2);
        // Verify exact expected canonical form.
        let expected =
            r#"{"a_field":{"deep":{"a":1,"b":2,"c":3}},"m_field":null,"z_field":[1,2,{"nested_a":"u","nested_b":"v"}]}"#;
        assert_eq!(std::str::from_utf8(&c1).unwrap(), expected);
    }

    #[test]
    fn utf16_codeunit_ordering_differs_from_byte_ordering() {
        // U+007E (~) byte = 0x7E
        // U+00C0 (À) bytes = 0xC3 0x80; UTF-16 code unit = 0x00C0
        // Byte order: "À" (0xC3) > "~" (0x7E). UTF-16 also: 0x00C0 > 0x007E. Same here.
        //
        // The interesting case: surrogate pair vs BMP char.
        // U+FFFD (replacement) UTF-16 code unit = 0xFFFD
        // U+1F600 (😀)         UTF-16 code units = 0xD83D 0xDE00. First unit 0xD83D < 0xFFFD.
        // So in UTF-16 order, 😀 < U+FFFD; in byte order (UTF-8), 😀 = F0 9F 98 80 vs FFFD = EF BF BD.
        // First byte F0 > EF, so byte order: 😀 > U+FFFD. Different from UTF-16 order.
        let v = json!({"\u{FFFD}": 1, "\u{1F600}": 2});
        let canon = canonical_json(&v);
        let s = std::str::from_utf8(&canon).unwrap();
        // UTF-16 order puts 😀 first.
        assert!(s.starts_with("{\"\u{1F600}\":2"));
    }

    #[test]
    fn round_trip_via_serde_json_parse() {
        // canonical output must be valid JSON parsable back to identical Value.
        let v = json!({"users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}], "count": 2});
        let canon = canonical_json(&v);
        let reparsed: Value = serde_json::from_slice(&canon).unwrap();
        assert_eq!(reparsed, v);
    }

    #[test]
    fn map_vs_struct_serialization_equivalent() {
        // Verify that the same logical data produces identical canonical bytes
        // whether constructed via json! macro or via insertion-order-varying map.
        use serde_json::Map;
        let mut m1 = Map::new();
        m1.insert("c".to_string(), json!(3));
        m1.insert("a".to_string(), json!(1));
        m1.insert("b".to_string(), json!(2));
        let v_map = Value::Object(m1);

        let v_json = json!({"a": 1, "b": 2, "c": 3});

        assert_eq!(canonical_json(&v_map), canonical_json(&v_json));
        assert_eq!(canonical_json(&v_map), br#"{"a":1,"b":2,"c":3}"#);
    }
}
