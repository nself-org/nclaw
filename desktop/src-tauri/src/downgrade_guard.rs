// downgrade_guard.rs — rejects updater manifests whose version is <= current app version.
//
// WHY: Tauri 2 updater does not guard against downgrade attacks. A manifest published
// manually (workflow_dispatch) against an old tag or a compromised R2 upload could
// silently roll users back to a version with known vulnerabilities.
//
// HOW: parse both versions as semver and reject if manifest_version <= current.

use semver::Version;

/// Error returned when an update would be a downgrade.
#[derive(Debug, PartialEq)]
pub struct DowngradeError {
    pub current: String,
    pub offered: String,
}

impl std::fmt::Display for DowngradeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "downgrade rejected: offered {} <= current {}",
            self.offered, self.current
        )
    }
}

impl std::error::Error for DowngradeError {}

/// Returns `Ok(())` when `offered_version` is strictly greater than `current_version`.
/// Returns `Err(DowngradeError)` when `offered_version <= current_version`.
///
/// Both strings must be valid semver (e.g. "1.1.2", "2.0.0-beta.1").
pub fn check_version(
    current_version: &str,
    offered_version: &str,
) -> Result<(), DowngradeError> {
    let current = Version::parse(current_version).unwrap_or_else(|_| Version::new(0, 0, 0));
    let offered = Version::parse(offered_version).unwrap_or_else(|_| Version::new(0, 0, 0));

    if offered > current {
        Ok(())
    } else {
        Err(DowngradeError {
            current: current_version.to_owned(),
            offered: offered_version.to_owned(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- upgrade is allowed ---

    #[test]
    fn upgrade_patch_is_allowed() {
        assert!(check_version("1.1.1", "1.1.2").is_ok());
    }

    #[test]
    fn upgrade_minor_is_allowed() {
        assert!(check_version("1.1.1", "1.2.0").is_ok());
    }

    #[test]
    fn upgrade_major_is_allowed() {
        assert!(check_version("1.1.1", "2.0.0").is_ok());
    }

    // --- same version is rejected ---

    #[test]
    fn same_version_is_rejected() {
        let err = check_version("1.1.2", "1.1.2").unwrap_err();
        assert_eq!(err.offered, "1.1.2");
        assert_eq!(err.current, "1.1.2");
    }

    // --- downgrades are rejected ---

    #[test]
    fn downgrade_patch_is_rejected() {
        let err = check_version("1.1.2", "1.1.1").unwrap_err();
        assert_eq!(err.offered, "1.1.1");
        assert_eq!(err.current, "1.1.2");
    }

    #[test]
    fn downgrade_minor_is_rejected() {
        let err = check_version("1.2.0", "1.1.9").unwrap_err();
        assert_eq!(err.offered, "1.1.9");
    }

    #[test]
    fn downgrade_major_is_rejected() {
        let err = check_version("2.0.0", "1.9.9").unwrap_err();
        assert_eq!(err.offered, "1.9.9");
    }

    // --- prerelease semantics (semver: 1.1.2-beta.1 < 1.1.2) ---

    #[test]
    fn prerelease_to_stable_same_base_is_allowed() {
        // semver: 1.1.2-beta.1 < 1.1.2 — stable is an upgrade from prerelease
        assert!(check_version("1.1.2-beta.1", "1.1.2").is_ok());
    }

    #[test]
    fn stable_to_lower_prerelease_rejected() {
        // 1.1.2-beta.1 < 1.1.2; offering it to a stable user is a downgrade
        let err = check_version("1.1.2", "1.1.2-beta.1").unwrap_err();
        assert_eq!(err.offered, "1.1.2-beta.1");
    }

    // --- malformed version falls back to 0.0.0 ---

    #[test]
    fn malformed_offered_version_is_rejected() {
        // "garbage" parses to 0.0.0 which is <= any real version
        let err = check_version("1.0.0", "garbage").unwrap_err();
        assert_eq!(err.offered, "garbage");
    }

    #[test]
    fn malformed_current_falls_back_to_zero_zero_zero() {
        // current is "garbage" → 0.0.0; offered "1.0.0" > 0.0.0 → allowed
        assert!(check_version("garbage", "1.0.0").is_ok());
    }

    // --- display format ---

    #[test]
    fn error_display_includes_both_versions() {
        let err = check_version("1.1.2", "1.1.1").unwrap_err();
        let msg = err.to_string();
        assert!(msg.contains("1.1.1"), "offered missing from: {msg}");
        assert!(msg.contains("1.1.2"), "current missing from: {msg}");
        assert!(msg.contains("downgrade rejected"), "prefix missing from: {msg}");
    }
}
