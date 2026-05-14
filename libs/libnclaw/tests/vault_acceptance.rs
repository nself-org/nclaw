//! S18.T10 Acceptance tests for vault subsystem

use libnclaw::vault::*;
use uuid::Uuid;

#[test]
fn test_rotation_cadence_daily() {
    use chrono::Utc;

    let now = Utc::now();
    let next = next_rotation_at(now, RotationCadence::Daily);
    let diff = next.signed_duration_since(now);

    assert!(diff.num_hours() >= 23 && diff.num_hours() <= 25, "Daily should rotate ~24h later");
}

#[test]
fn test_rotation_cadence_weekly() {
    use chrono::Utc;

    let now = Utc::now();
    let next = next_rotation_at(now, RotationCadence::Weekly);
    let diff = next.signed_duration_since(now);

    assert!(diff.num_days() >= 6 && diff.num_days() <= 8, "Weekly should rotate ~7d later");
}

#[test]
fn test_rotation_cadence_monthly() {
    use chrono::Utc;

    let now = Utc::now();
    let next = next_rotation_at(now, RotationCadence::Monthly);
    let diff = next.signed_duration_since(now);

    assert!(diff.num_days() >= 29 && diff.num_days() <= 31, "Monthly should rotate ~30d later");
}

#[test]
fn test_rotation_cadence_manual() {
    use chrono::Utc;

    let now = Utc::now();
    let next = next_rotation_at(now, RotationCadence::Manual);
    let diff = next.signed_duration_since(now);

    // Manual should be so far in future that it's effectively never
    assert!(diff.num_days() > 36000, "Manual should be 100+ years away");
}

#[test]
fn test_should_rotate_now_future() {
    use chrono::Utc;

    let future = Utc::now() + chrono::Duration::hours(1);
    let should_rotate = should_rotate_now(future, RotationCadence::Daily);

    assert!(!should_rotate, "Future rotation time should not trigger");
}

#[test]
fn test_registration_request_shape() {
    let reg = DeviceRegistration {
        device_pubkey: vec![1, 2, 3, 4],
        label: "my-laptop".to_string(),
        platform: "macos".to_string(),
    };

    assert!(!reg.device_pubkey.is_empty());
    assert!(!reg.label.is_empty());
    assert!(!reg.platform.is_empty());
}

#[test]
fn test_vault_envelope_shape() {
    let env = VaultEnvelope {
        record_id: Uuid::new_v4(),
        envelope_ciphertext: vec![1, 2, 3],
        envelope_nonce: vec![4, 5, 6],
    };

    assert!(!env.envelope_ciphertext.is_empty());
    assert!(!env.envelope_nonce.is_empty());
}

#[test]
fn test_vault_telemetry_counters() {
    let telemetry = VaultTelemetry::new();

    telemetry.inc_sealed();
    telemetry.inc_sealed();
    telemetry.inc_opened();
    telemetry.inc_registered();
    telemetry.inc_revoked();

    let snap = telemetry.snapshot();
    assert_eq!(snap.envelopes_sealed, 2);
    assert_eq!(snap.envelopes_opened, 1);
    assert_eq!(snap.devices_registered, 1);
    assert_eq!(snap.devices_revoked, 1);
}

#[test]
fn test_vault_telemetry_snapshot_independence() {
    let telemetry = VaultTelemetry::new();
    telemetry.inc_sealed();

    let snap1 = telemetry.snapshot();
    assert_eq!(snap1.envelopes_sealed, 1);

    telemetry.inc_sealed();
    let snap2 = telemetry.snapshot();

    // Snapshot is immutable; snap1 should not reflect the second increment
    assert_eq!(snap1.envelopes_sealed, 1);
    assert_eq!(snap2.envelopes_sealed, 2);
}
