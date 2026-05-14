//! Privacy filter for frontier dispatch.
//!
//! S19.T07: Strips personally identifiable information (PII) before sending
//! prompts to cloud/frontier providers. Implements naive regex-based filtering
//! for emails, phone numbers, and SSNs. Future: NER-based approach in v1.2.0.

/// Strip common PII patterns from text using naive regex approach.
///
/// Redacts:
/// - Email addresses (emails@example.com)
/// - US-style phone numbers (123-456-7890, 123.456.7890, 123 456 7890)
/// - US Social Security Numbers (123-45-6789)
///
/// Returns the input with PII replaced by placeholder tokens.
///
/// **Note:** This is v1.1.1 naive filtering. v1.2.0 will add NER-based
/// fine-grained extraction. Only use this for basic privacy protection.
pub fn strip_pii(input: &str) -> String {
    let mut result = input.to_string();

    // Email addresses: word chars + dots/plus/hyphens @ domain . TLD
    result = strip_emails(&result);

    // US phone numbers: 123-456-7890, 123.456.7890, 123 456 7890
    result = strip_us_phones(&result);

    // SSN: 123-45-6789
    result = strip_ssn(&result);

    result
}

fn strip_emails(input: &str) -> String {
    let mut result = String::new();
    let mut chars = input.chars().peekable();

    while let Some(ch) = chars.next() {
        // Naive heuristic: look for patterns like "word@domain.tld"
        if is_email_char(ch) {
            let start_pos = result.len();
            let mut candidate = ch.to_string();

            while let Some(&next) = chars.peek() {
                if is_email_char(next) || next == '@' {
                    candidate.push(next);
                    chars.next();
                } else if next == '.' {
                    // Tentatively include dots
                    candidate.push(next);
                    chars.next();
                } else {
                    break;
                }
            }

            // Check if it looks like an email (has @ and at least one dot after)
            if candidate.contains('@') && candidate.contains('.') {
                result.push_str("[EMAIL]");
            } else {
                result.push_str(&candidate);
            }
        } else {
            result.push(ch);
        }
    }

    result
}

fn is_email_char(ch: char) -> bool {
    ch.is_alphanumeric() || ch == '_' || ch == '-' || ch == '+'
}

fn strip_us_phones(input: &str) -> String {
    let mut result = String::new();
    let mut chars = input.chars().peekable();

    while let Some(ch) = chars.next() {
        if ch.is_ascii_digit() {
            let mut candidate = ch.to_string();
            let mut digit_count = 1;

            while let Some(&next) = chars.peek() {
                if next.is_ascii_digit() {
                    candidate.push(next);
                    digit_count += 1;
                    chars.next();
                } else if (next == '-' || next == '.' || next == ' ') && digit_count < 10 {
                    // Separator in a potential phone
                    candidate.push(next);
                    chars.next();
                } else {
                    break;
                }
            }

            // Check if it matches ~10 digits with separators (US phone pattern)
            let digit_only: String = candidate.chars().filter(|c| c.is_ascii_digit()).collect();
            if digit_only.len() == 10 {
                result.push_str("[PHONE]");
            } else {
                result.push_str(&candidate);
            }
        } else {
            result.push(ch);
        }
    }

    result
}

fn strip_ssn(input: &str) -> String {
    let mut result = String::new();
    let mut chars = input.chars().peekable();

    while let Some(ch) = chars.next() {
        if ch.is_ascii_digit() {
            let mut candidate = ch.to_string();
            let mut digits = vec![ch];

            while let Some(&next) = chars.peek() {
                if next.is_ascii_digit() {
                    candidate.push(next);
                    digits.push(next);
                    chars.next();
                } else if (next == '-') && digits.len() < 9 {
                    candidate.push(next);
                    chars.next();
                } else {
                    break;
                }
            }

            // SSN is xxx-xx-xxxx = 3 digits + dash + 2 digits + dash + 4 digits
            let digit_only: String = digits.iter().collect();
            if digit_only.len() == 9 {
                result.push_str("[SSN]");
            } else {
                result.push_str(&candidate);
            }
        } else {
            result.push(ch);
        }
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn privacy_filter_strips_email() {
        let input = "Contact me at alice@example.com for details.";
        let output = strip_pii(input);
        assert!(output.contains("[EMAIL]"));
        assert!(!output.contains("alice"));
    }

    #[test]
    fn privacy_filter_strips_phone() {
        let input = "Call me at 555-123-4567 anytime.";
        let output = strip_pii(input);
        assert!(output.contains("[PHONE]"));
        assert!(!output.contains("5551234567"));
    }

    #[test]
    fn privacy_filter_strips_ssn() {
        let input = "My SSN is 123-45-6789.";
        let output = strip_pii(input);
        assert!(output.contains("[SSN]"));
        assert!(!output.contains("123-45-6789"));
    }

    #[test]
    fn privacy_filter_preserves_non_pii() {
        let input = "This is a normal sentence with no secrets.";
        let output = strip_pii(input);
        assert_eq!(input, output);
    }

    #[test]
    fn privacy_filter_multiple_pii() {
        let input = "Contact alice@example.com or call 555-123-4567. SSN: 123-45-6789";
        let output = strip_pii(input);
        assert!(output.contains("[EMAIL]"));
        assert!(output.contains("[PHONE]"));
        assert!(output.contains("[SSN]"));
    }

    #[test]
    fn privacy_filter_ignores_partial_patterns() {
        // Not enough digits for a full phone
        let input = "Extension 123-45";
        let output = strip_pii(input);
        assert_eq!(input, output);
    }
}
