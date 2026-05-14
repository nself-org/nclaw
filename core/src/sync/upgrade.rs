//! Schema version negotiation and compatibility checking.
//!
//! Determines if client and server are compatible, or if one needs to upgrade.

use serde::{Deserialize, Serialize};

/// Result of compatibility check between client and server versions.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum CompatStatus {
    /// Client and server versions are compatible.
    Compatible,
    /// Client version is too old; user should upgrade the app.
    ClientNeedsUpgrade,
    /// Server version is too old; server operator should upgrade.
    ServerNeedsUpgrade,
}

/// Check compatibility between server and client schema versions.
///
/// Compatibility rules (to be finalized per sync-protocol spec):
/// - Same major version = compatible
/// - Client minor < server minor = compatible (backward compatible)
/// - Client minor > server minor = ServerNeedsUpgrade
/// - Major version mismatch = appropriate direction upgrade needed
///
/// For now: versions must match exactly for compatibility.
pub fn check_compat(server_version: u32, client_version: u32) -> CompatStatus {
    if server_version == client_version {
        CompatStatus::Compatible
    } else if client_version > server_version {
        CompatStatus::ServerNeedsUpgrade
    } else {
        CompatStatus::ClientNeedsUpgrade
    }
}

/// Decode version number as (major, minor, patch).
///
/// Format: version_u32 where high byte is major, next byte is minor, low word is patch.
/// Stub: returns (version >> 16, (version >> 8) & 0xFF, version & 0xFF).
pub fn decode_version(version: u32) -> (u8, u8, u16) {
    let major = (version >> 16) as u8;
    let minor = ((version >> 8) & 0xFF) as u8;
    let patch = (version & 0xFF) as u16;
    (major, minor, patch)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compatible_same_version() {
        assert_eq!(check_compat(1, 1), CompatStatus::Compatible);
    }

    #[test]
    fn client_needs_upgrade() {
        assert_eq!(check_compat(2, 1), CompatStatus::ClientNeedsUpgrade);
    }

    #[test]
    fn server_needs_upgrade() {
        assert_eq!(check_compat(1, 2), CompatStatus::ServerNeedsUpgrade);
    }

    #[test]
    fn decode_version_extracts_parts() {
        let version = 0x010203u32; // major=1, minor=2, patch=3
        let (major, minor, patch) = decode_version(version);
        assert_eq!(major, 1);
        assert_eq!(minor, 2);
        assert_eq!(patch, 3);
    }

    #[test]
    fn decode_version_high_patch() {
        let version = 0x0102FFu32; // major=1, minor=2, patch=255
        let (major, minor, patch) = decode_version(version);
        assert_eq!(major, 1);
        assert_eq!(minor, 2);
        assert_eq!(patch, 255);
    }
}
