//! Source-account scoping helper.
//!
//! Per Multi-Tenant Convention Wall in nSelf PPI:
//! `source_account_id` separates apps within one nself deploy (ɳClaw vs ɳTask vs ɳChat).
//! It is NOT cloud multi-tenancy — that's `tenant_id` + Hasura row filters.
//!
//! This module provides the `AccountScope` struct to simplify SQL filtering by app.

/// Represents the source account (app instance) scope for a query.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct AccountScope {
    /// App identifier (e.g., "nclaw", "primary")
    pub source_account_id: String,
}

impl AccountScope {
    /// Well-known scope constant for nClaw app.
    pub const NCLAW: &'static str = "nclaw";
    /// Well-known scope constant for primary/default app.
    pub const PRIMARY: &'static str = "primary";

    /// Create a scope for the nClaw app.
    pub fn nclaw() -> Self {
        Self {
            source_account_id: Self::NCLAW.into(),
        }
    }

    /// Create a scope for the primary/default app.
    pub fn primary() -> Self {
        Self {
            source_account_id: Self::PRIMARY.into(),
        }
    }

    /// Create a scope for a custom app ID.
    pub fn for_app(app_id: impl Into<String>) -> Self {
        Self {
            source_account_id: app_id.into(),
        }
    }

    /// Generate a SQL WHERE-clause fragment for this scope (Postgres + SQLite syntax).
    /// Properly escapes single quotes in the app ID.
    ///
    /// Example: `AccountScope::nclaw().sql_filter()` → `"source_account_id = 'nclaw'"`
    pub fn sql_filter(&self) -> String {
        let escaped = self.source_account_id.replace('\'', "''");
        format!("source_account_id = '{}'", escaped)
    }
}

impl std::fmt::Display for AccountScope {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.source_account_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn account_scope_nclaw() {
        let scope = AccountScope::nclaw();
        assert_eq!(scope.source_account_id, "nclaw");
        assert_eq!(scope.sql_filter(), "source_account_id = 'nclaw'");
    }

    #[test]
    fn account_scope_primary() {
        let scope = AccountScope::primary();
        assert_eq!(scope.source_account_id, "primary");
        assert_eq!(scope.sql_filter(), "source_account_id = 'primary'");
    }

    #[test]
    fn account_scope_custom() {
        let scope = AccountScope::for_app("my-app");
        assert_eq!(scope.source_account_id, "my-app");
        assert_eq!(scope.sql_filter(), "source_account_id = 'my-app'");
    }

    #[test]
    fn account_scope_sql_filter_escapes_quotes() {
        let scope = AccountScope::for_app("test'app");
        assert_eq!(scope.sql_filter(), "source_account_id = 'test''app'");
    }

    #[test]
    fn account_scope_sql_filter_multiple_quotes() {
        let scope = AccountScope::for_app("a'b'c");
        assert_eq!(scope.sql_filter(), "source_account_id = 'a''b''c'");
    }

    #[test]
    fn account_scope_display() {
        let scope = AccountScope::for_app("test-app");
        assert_eq!(scope.to_string(), "test-app");
    }

    #[test]
    fn account_scope_equality() {
        let s1 = AccountScope::nclaw();
        let s2 = AccountScope::for_app("nclaw");
        assert_eq!(s1, s2);
    }

    #[test]
    fn account_scope_hash() {
        use std::collections::HashSet;
        let mut set = HashSet::new();
        set.insert(AccountScope::nclaw());
        set.insert(AccountScope::nclaw()); // duplicate
        assert_eq!(set.len(), 1); // deduped
    }
}
