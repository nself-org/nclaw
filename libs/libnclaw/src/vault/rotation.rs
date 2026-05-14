//! Envelope rotation policy — define when per-device envelopes expire and should be rotated

use chrono::{DateTime, Duration, Utc};

/// Rotation cadence options
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RotationCadence {
    Manual,
    Daily,
    Weekly,
    Monthly,
}

/// Calculate the next rotation time given the last rotation and cadence.
pub fn next_rotation_at(last_at: DateTime<Utc>, cadence: RotationCadence) -> DateTime<Utc> {
    match cadence {
        RotationCadence::Manual => last_at + Duration::days(365 * 100), // effectively never
        RotationCadence::Daily => last_at + Duration::days(1),
        RotationCadence::Weekly => last_at + Duration::weeks(1),
        RotationCadence::Monthly => last_at + Duration::days(30),
    }
}

/// Check if rotation is now due given the last rotation time and cadence.
pub fn should_rotate_now(last_at: DateTime<Utc>, cadence: RotationCadence) -> bool {
    Utc::now() >= next_rotation_at(last_at, cadence)
}
