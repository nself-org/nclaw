use std::path::PathBuf;

#[test]
fn test_load_grammars_from_manifest() {
    // Use CARGO_MANIFEST_DIR to locate the grammars/ directory relative to Cargo.toml
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let grammars_dir = PathBuf::from(manifest_dir).join("grammars");

    let grammars =
        libnclaw::llm::Grammars::load_from(&grammars_dir).expect("should load grammars from disk");

    assert!(
        !grammars.json().is_empty(),
        "JSON grammar should not be empty"
    );
    assert!(
        grammars.json().contains("root   ::= object"),
        "JSON grammar should define root rule"
    );
}

#[test]
fn test_parse_tool_call_valid() {
    let json = r#"{"tool":"send_email","args":{"to":"user@example.com","subject":"Test"}}"#;
    let call = libnclaw::llm::parse_tool_call(json).expect("should parse valid tool call");

    assert_eq!(call.tool, "send_email", "tool name mismatch");
    assert_eq!(call.args["to"], "user@example.com", "args.to mismatch");
}

#[test]
fn test_parse_tool_call_malformed() {
    let json = r#"{"tool":"send_email""#; // truncated
    let result = libnclaw::llm::parse_tool_call(json);

    assert!(result.is_err(), "should fail on malformed JSON");
    let err_msg = result.unwrap_err();
    assert!(
        err_msg.contains("invalid tool call"),
        "error message should be descriptive"
    );
}

#[test]
fn test_parse_tool_call_missing_tool_field() {
    let json = r#"{"args":{"to":"user@example.com"}}"#;
    let result = libnclaw::llm::parse_tool_call(json);

    assert!(result.is_err(), "should fail when 'tool' field is missing");
}

#[test]
fn test_parse_tool_call_missing_args_field() {
    let json = r#"{"tool":"send_email"}"#;
    let result = libnclaw::llm::parse_tool_call(json);

    // Depending on implementation, this might be lenient. We test that it either succeeds
    // with null args or fails. For strict parsing, it should fail.
    match result {
        Ok(call) => {
            // If lenient, args should be null or missing
            assert_eq!(call.tool, "send_email");
        }
        Err(e) => {
            // If strict, error is acceptable
            assert!(e.contains("invalid tool call") || e.contains("missing"));
        }
    }
}

#[test]
fn test_tool_call_with_allowlist_single() {
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let grammars_dir = PathBuf::from(manifest_dir).join("grammars");

    let grammars = libnclaw::llm::Grammars::load_from(&grammars_dir).expect("should load grammars");

    let allowlist = vec!["send_email".to_string()];
    let grammar = grammars.tool_call_with_allowlist(&allowlist);

    assert!(
        grammar.contains(r#"\"send_email\""#),
        "grammar should contain escaped tool name"
    );
    assert!(
        !grammar.contains("[a-z0-9_-]+"),
        "grammar should NOT contain wildcard pattern when allowlist is set"
    );
}

#[test]
fn test_tool_call_with_allowlist_multiple() {
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let grammars_dir = PathBuf::from(manifest_dir).join("grammars");

    let grammars = libnclaw::llm::Grammars::load_from(&grammars_dir).expect("should load grammars");

    let allowlist = vec![
        "send_email".to_string(),
        "read_inbox".to_string(),
        "schedule".to_string(),
    ];
    let grammar = grammars.tool_call_with_allowlist(&allowlist);

    // All three tool names should be present
    assert!(grammar.contains(r#"\"send_email\""#));
    assert!(grammar.contains(r#"\"read_inbox\""#));
    assert!(grammar.contains(r#"\"schedule\""#));

    // Should use alternation (|) operator
    assert!(
        grammar.contains("|"),
        "grammar should use alternation for multiple tools"
    );

    // Wildcard should be replaced
    assert!(
        !grammar.contains("[a-z0-9_-]+"),
        "wildcard should not remain in constrained grammar"
    );
}

#[test]
fn test_tool_call_with_allowlist_empty() {
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let grammars_dir = PathBuf::from(manifest_dir).join("grammars");

    let grammars = libnclaw::llm::Grammars::load_from(&grammars_dir).expect("should load grammars");

    let allowlist: Vec<String> = vec![];
    let grammar = grammars.tool_call_with_allowlist(&allowlist);

    // Empty allowlist should return template unchanged
    assert!(
        grammar.contains("[a-z0-9_-]+"),
        "empty allowlist should preserve wildcard pattern"
    );
}

#[test]
fn test_json_grammar_structure() {
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let grammars_dir = PathBuf::from(manifest_dir).join("grammars");

    let grammars = libnclaw::llm::Grammars::load_from(&grammars_dir).expect("should load grammars");

    let json_grammar = grammars.json();

    // Check for key rule definitions
    assert!(json_grammar.contains("root   ::= object"));
    assert!(json_grammar.contains("value  ::="));
    assert!(json_grammar.contains("object ::="));
    assert!(json_grammar.contains("array  ::="));
    assert!(json_grammar.contains("string ::="));
    assert!(json_grammar.contains("number ::="));
    assert!(json_grammar.contains("ws ::="));
}

#[test]
fn test_tool_call_round_trip() {
    let original =
        r#"{"tool":"classify_email","args":{"from":"sender@example.com","subject":"Check this"}}"#;
    let call = libnclaw::llm::parse_tool_call(original).expect("should parse original JSON");

    // Serialize back to JSON
    let serialized = serde_json::to_string(&call).expect("should serialize back to JSON");

    // Re-parse to verify consistency
    let reparsed =
        libnclaw::llm::parse_tool_call(&serialized).expect("should re-parse serialized JSON");

    assert_eq!(
        call.tool, reparsed.tool,
        "tool name should match after round trip"
    );
    assert_eq!(
        call.args, reparsed.args,
        "args should match after round trip"
    );
}
