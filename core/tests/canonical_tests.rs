//! Integration tests for libnclaw::sync::canonical — RFC 8785 JSON canonicalization.
//!
//! Verifies byte-stable JSON serialization used in signing material.
//! Companion Go implementation: plugins-pro/paid/nself-sync/internal/auth/canonical.go

use libnclaw::sync::canonical::canonical_json;
use serde_json::{json, Value};

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
    assert_eq!(canon, br#""a\"b\\c\nd\re\tf\bg\fh""#);
}

#[test]
fn control_char_hex_escape() {
    let v = json!("\u{0001}\u{001f}");
    // RFC 8785 §3.2.2.2: U+0000..U+001F must be \u00XX escaped (lowercase hex).
    assert_eq!(canonical_json(&v), br#""\u0001\u001f""#);
}

#[test]
fn unicode_passthrough_no_escape() {
    // U+00E9 (é) and U+4E2D (中) emit as UTF-8 bytes verbatim.
    let v = json!("é中");
    let canon = canonical_json(&v);
    assert_eq!(canon, &[b'"', 0xC3, 0xA9, 0xE4, 0xB8, 0xAD, b'"'][..]);
}

#[test]
fn deeply_nested_golden_fixture() {
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
    let expected = r#"{"a_field":{"deep":{"a":1,"b":2,"c":3}},"m_field":null,"z_field":[1,2,{"nested_a":"u","nested_b":"v"}]}"#;
    assert_eq!(std::str::from_utf8(&c1).unwrap(), expected);
}

#[test]
fn utf16_codeunit_ordering_differs_from_byte_ordering() {
    // U+FFFD vs U+1F600: UTF-16 puts emoji first (0xD83D < 0xFFFD).
    let v = json!({"\u{FFFD}": 1, "\u{1F600}": 2});
    let canon = canonical_json(&v);
    let s = std::str::from_utf8(&canon).unwrap();
    assert!(s.starts_with("{\"\u{1F600}\":2"));
}

#[test]
fn round_trip_via_serde_json_parse() {
    let v =
        json!({"users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}], "count": 2});
    let canon = canonical_json(&v);
    let reparsed: Value = serde_json::from_slice(&canon).unwrap();
    assert_eq!(reparsed, v);
}

#[test]
fn map_vs_struct_serialization_equivalent() {
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
