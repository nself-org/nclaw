use serde::{Deserialize, Serialize};
use std::path::Path;

/// Generation constraint specifies how the LLM output should be restricted.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum GenerationConstraint {
    /// No output constraints.
    None,
    /// Stop after any of these token sequences.
    StopTokens(Vec<String>),
    /// Constrain output to valid JSON using GBNF grammar.
    Json,
    /// Constrain output to valid tool-call structure with allowed tools list.
    ToolCall { allowed_tools: Vec<String> },
}

/// Grammar templates loaded from disk at session init.
#[derive(Debug, Clone)]
pub struct Grammars {
    json: String,
    tool_call_template: String,
}

impl Grammars {
    /// Load grammars from the on-disk grammars/ directory.
    /// Returns error if either grammar file is missing or unreadable.
    pub fn load_from(dir: &Path) -> std::io::Result<Self> {
        Ok(Self {
            json: std::fs::read_to_string(dir.join("json.gbnf"))?,
            tool_call_template: std::fs::read_to_string(dir.join("tool_call.gbnf"))?,
        })
    }

    /// Return the JSON grammar as-is (no modification needed).
    pub fn json(&self) -> &str {
        &self.json
    }

    /// Build tool-call grammar enforcing an allowlist of tool names.
    /// Returns the grammar string with `tool-name` rule replaced by an alternation
    /// of the allowed tool names.
    pub fn tool_call_with_allowlist(&self, allowed: &[String]) -> String {
        if allowed.is_empty() {
            return self.tool_call_template.clone();
        }

        // Build alternation: ("tool1" | "tool2" | "tool3")
        let alt = allowed
            .iter()
            .map(|t| format!("\\\"{}\\\"", t))
            .collect::<Vec<_>>()
            .join(" | ");

        // Replace the wildcard tool-name rule with the allowlist alternation
        self.tool_call_template.replace(
            "tool-name   ::= \"\\\"\" [a-z0-9_-]+ \"\\\"\"",
            &format!("tool-name   ::= ({})", alt),
        )
    }
}

/// Parsed tool-call structure.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolCall {
    pub tool: String,
    pub args: serde_json::Value,
}

/// Parse a tool-call from JSON text.
/// Returns error if the text is not valid JSON or does not contain both `tool` and `args` fields.
pub fn parse_tool_call(text: &str) -> Result<ToolCall, String> {
    serde_json::from_str(text).map_err(|e| format!("invalid tool call: {}", e))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_tool_call_valid() {
        let json = r#"{"tool":"send_email","args":{"to":"test@example.com","body":"hello"}}"#;
        let call = parse_tool_call(json).expect("should parse");
        assert_eq!(call.tool, "send_email");
        assert_eq!(call.args["to"], "test@example.com");
    }

    #[test]
    fn test_parse_tool_call_invalid() {
        let json = r#"{"tool":"send_email""#; // malformed
        assert!(parse_tool_call(json).is_err());
    }

    #[test]
    fn test_parse_tool_call_missing_tool() {
        let json = r#"{"args":{"to":"test@example.com"}}"#;
        let result = parse_tool_call(json);
        assert!(result.is_err(), "should fail without 'tool' field");
    }

    #[test]
    fn test_tool_call_with_allowlist_empty() {
        let template = r#"tool-name   ::= "\"" [a-z0-9_-]+ "\"""#;
        let grammars = Grammars {
            json: String::new(),
            tool_call_template: template.to_string(),
        };
        let allowlist = vec![];
        let result = grammars.tool_call_with_allowlist(&allowlist);
        // Empty allowlist should return template unchanged
        assert_eq!(result, template);
    }

    #[test]
    fn test_tool_call_with_allowlist_single() {
        let template = r#"tool-name   ::= "\"" [a-z0-9_-]+ "\"""#;
        let grammars = Grammars {
            json: String::new(),
            tool_call_template: template.to_string(),
        };
        let allowlist = vec!["send_email".to_string()];
        let result = grammars.tool_call_with_allowlist(&allowlist);
        assert!(result.contains("(\\\"send_email\\\")"));
        assert!(!result.contains("[a-z0-9_-]+"));
    }

    #[test]
    fn test_tool_call_with_allowlist_multiple() {
        let template = r#"tool-name   ::= "\"" [a-z0-9_-]+ "\"""#;
        let grammars = Grammars {
            json: String::new(),
            tool_call_template: template.to_string(),
        };
        let allowlist = vec![
            "send_email".to_string(),
            "read_inbox".to_string(),
            "schedule".to_string(),
        ];
        let result = grammars.tool_call_with_allowlist(&allowlist);
        assert!(result.contains("(\\\"send_email\\\""));
        assert!(result.contains("\\\"read_inbox\\\""));
        assert!(result.contains("\\\"schedule\\\")"));
    }
}
