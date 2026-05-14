//! Smoke tests for client vault module: keypair, envelope, keychain

use libnclaw::error::CoreError;
use libnclaw::vault::keypair::{verify, DeviceKeypair};

#[test]
fn test_keypair_generate_and_sign() {
    let keypair = DeviceKeypair::generate();
    let message = b"test message for signing";

    let signature = keypair.sign(message);
    assert!(!signature.is_empty());
    assert_eq!(signature.len(), 64); // Ed25519 signature is 64 bytes
}

#[test]
fn test_keypair_roundtrip() {
    let kp1 = DeviceKeypair::generate();
    let secret_bytes = kp1.to_bytes();
    let public_bytes = kp1.public_bytes();

    let kp2 = DeviceKeypair::from_bytes(&secret_bytes).expect("should reconstruct");

    assert_eq!(kp2.to_bytes(), secret_bytes);
    assert_eq!(kp2.public_bytes(), public_bytes);
}

#[test]
fn test_signature_verify_match() {
    let keypair = DeviceKeypair::generate();
    let message = b"sign me";
    let signature = keypair.sign(message);
    let pubkey = keypair.public_bytes();

    let result = verify(&pubkey, message, &signature);
    assert!(result.is_ok());
}

#[test]
fn test_signature_verify_fails_on_tamper() {
    let keypair = DeviceKeypair::generate();
    let message = b"original message";
    let signature = keypair.sign(message);
    let pubkey = keypair.public_bytes();

    let tampered = b"different message";
    let result = verify(&pubkey, tampered, &signature);

    assert!(result.is_err());
}

#[test]
#[cfg(feature = "vault")]
fn test_envelope_roundtrip() {
    use libnclaw::vault::envelope::{open, seal};

    let key = &[99u8; 32];
    let plaintext = b"secret vault content";

    let envelope = seal(key, plaintext).expect("seal should work");
    let decrypted = open(key, &envelope).expect("open should work");

    assert_eq!(decrypted, plaintext);
}

#[test]
#[cfg(feature = "vault")]
fn test_envelope_wrong_key_fails() {
    use libnclaw::vault::envelope::{open, seal};

    let key1 = &[99u8; 32];
    let key2 = &[100u8; 32];
    let plaintext = b"protected";

    let envelope = seal(key1, plaintext).expect("seal should work");
    let result = open(key2, &envelope);

    assert!(result.is_err());
}
