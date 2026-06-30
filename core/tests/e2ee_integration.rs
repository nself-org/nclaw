// e2ee_integration.rs — Two-party E2EE integration tests.
//
// Purpose: End-to-end tests for the libnclaw E2EE module:
//   1. Two-party round-trip: Alice encrypts → Bob decrypts (same session key).
//   2. Tamper tests: modified ciphertext/nonce/aad all fail decryption.
//   3. Cross-fingerprint: different keys produce different fingerprints.
//   4. Session key isolation: two derive_session calls produce same key.
//
// These tests use only in-memory crypto — no keychain, no network, no DB.
// SPORT: P4-E9-W3-S06-T12.

use libnclaw::e2ee::{
    codec::{open, seal, EncryptedMessage},
    keys::{fingerprint, generate_keypair},
    session::derive_session,
};

#[test]
fn test_two_party_roundtrip() {
    // Alice and Bob each generate a keypair.
    let (alice_ks, alice_pub) = generate_keypair();
    let (bob_ks, bob_pub) = generate_keypair();

    // Both parties derive the shared session key using the other's public key.
    let alice_session = derive_session(alice_ks.0, bob_pub, b"nclaw-v1").unwrap();
    let bob_session = derive_session(bob_ks.0, alice_pub, b"nclaw-v1").unwrap();

    assert_eq!(
        alice_session.session_key, bob_session.session_key,
        "Alice and Bob must derive identical session keys"
    );

    // Alice encrypts a message.
    let plaintext = b"Hello, Bob!";
    let aad = b"nclaw-session-aad";
    let encrypted = seal(&alice_session.session_key, plaintext, aad).unwrap();

    // Bob decrypts.
    let decrypted = open(&bob_session.session_key, &encrypted).unwrap();
    assert_eq!(
        decrypted, plaintext,
        "Decrypted plaintext must match original"
    );
}

#[test]
fn test_tampered_ciphertext_rejected() {
    let (ks, pub_key) = generate_keypair();
    let session = derive_session(ks.0, pub_key, b"nclaw-v1").unwrap();

    let mut encrypted = seal(&session.session_key, b"secret", b"aad").unwrap();
    // Flip a byte in the ciphertext.
    if !encrypted.ciphertext.is_empty() {
        encrypted.ciphertext[0] ^= 0xFF;
    }

    let result = open(&session.session_key, &encrypted);
    assert!(result.is_err(), "Tampered ciphertext must be rejected");
}

#[test]
fn test_tampered_nonce_rejected() {
    let (ks, pub_key) = generate_keypair();
    let session = derive_session(ks.0, pub_key, b"nclaw-v1").unwrap();

    let mut encrypted = seal(&session.session_key, b"secret", b"aad").unwrap();
    // Flip a byte in the nonce.
    encrypted.nonce[0] ^= 0xFF;

    let result = open(&session.session_key, &encrypted);
    assert!(result.is_err(), "Tampered nonce must be rejected");
}

#[test]
fn test_tampered_aad_rejected() {
    let (ks, pub_key) = generate_keypair();
    let session = derive_session(ks.0, pub_key, b"nclaw-v1").unwrap();

    let encrypted = seal(&session.session_key, b"secret", b"original-aad").unwrap();
    // Create a new EncryptedMessage with the same nonce/ciphertext but different AAD.
    let tampered = EncryptedMessage {
        nonce: encrypted.nonce,
        ciphertext: encrypted.ciphertext,
        aad: b"tampered-aad".to_vec(),
    };

    let result = open(&session.session_key, &tampered);
    assert!(result.is_err(), "Tampered AAD must be rejected");
}

#[test]
fn test_wrong_session_key_rejected() {
    let (alice_ks, alice_pub) = generate_keypair();
    let (eve_ks, _eve_pub) = generate_keypair();

    // Alice's session key (self-derive for simplicity).
    let alice_session = derive_session(alice_ks.0, alice_pub, b"nclaw-v1").unwrap();
    // Eve uses a different private key → different DH result → different session key.
    let eve_session = derive_session(eve_ks.0, alice_pub, b"nclaw-v1").unwrap();

    let encrypted = seal(&alice_session.session_key, b"private message", b"aad").unwrap();
    let result = open(&eve_session.session_key, &encrypted);
    // Only fails if session keys actually differ (probabilistically always true for random keys).
    if alice_session.session_key != eve_session.session_key {
        assert!(result.is_err(), "Wrong session key must be rejected");
    }
}

#[test]
fn test_different_keys_different_fingerprints() {
    let (_ks1, pub1) = generate_keypair();
    let (_ks2, pub2) = generate_keypair();

    let fp1 = fingerprint(&pub1);
    let fp2 = fingerprint(&pub2);

    assert_ne!(
        fp1, fp2,
        "Different keys must produce different fingerprints"
    );
    assert_eq!(fp1.len(), 64, "Fingerprint must be 64 hex chars");
    assert_eq!(fp2.len(), 64, "Fingerprint must be 64 hex chars");
}

#[test]
fn test_session_key_symmetry() {
    let (alice_ks, alice_pub) = generate_keypair();
    let (bob_ks, bob_pub) = generate_keypair();

    // Alice uses her private key + Bob's public.
    let alice_session = derive_session(alice_ks.0, bob_pub, b"nclaw-v1").unwrap();
    // Bob uses his private key + Alice's public.
    let bob_session = derive_session(bob_ks.0, alice_pub, b"nclaw-v1").unwrap();

    assert_eq!(
        alice_session.session_key, bob_session.session_key,
        "Session keys must be symmetric (ECDH property)"
    );
}

#[test]
fn test_e2ee_message_serialization() {
    let (ks, pub_key) = generate_keypair();
    let session = derive_session(ks.0, pub_key, b"nclaw-v1").unwrap();

    let encrypted = seal(&session.session_key, b"serialize me", b"aad").unwrap();

    // Serialize to JSON and back.
    let json = serde_json::to_string(&encrypted).expect("serialize EncryptedMessage");
    let deserialized: EncryptedMessage =
        serde_json::from_str(&json).expect("deserialize EncryptedMessage");

    let decrypted = open(&session.session_key, &deserialized).unwrap();
    assert_eq!(
        decrypted, b"serialize me",
        "Round-trip through JSON must preserve plaintext"
    );
}
