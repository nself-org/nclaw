//! libnclaw-server — Unix socket JSON-RPC sidecar for E2EE operations.
//!
//! Purpose: Expose libnclaw E2EE functions (encrypt, decrypt, derive_session)
//!          over a Unix domain socket as newline-delimited JSON-RPC 2.0.
//!          The Go intelligence service connects here to perform E2EE without cgo.
//!          Per OD-3 in open-decisions-resolved.md (sidecar model).
//!
//! Inputs:  LIBNCLAW_SOCKET_PATH env var (default: /tmp/libnclaw.sock)
//!          NSELF_ENV env var (for log level selection)
//!          NCLAW_SENTRY_DSN env var (optional — conditional Sentry init)
//! Outputs: JSON-RPC 2.0 responses on socket; stderr slog JSON logs.
//! Constraints: Never log decrypted plaintext or key material.
//!              Error responses use code -32603 (internal) — no detail in message.
//! SPORT: REGISTRY-SERVICES.md — libnclaw-server, socket=/tmp/libnclaw.sock.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixListener;
use std::path::PathBuf;

use libnclaw::e2ee::{
    derive_session, generate_keypair, open, seal, E2EEError, NCLAW_HKDF_INFO,
};
use serde::{Deserialize, Serialize};

// ── JSON-RPC 2.0 types ─────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct RpcRequest {
    jsonrpc: String,
    method: String,
    params: serde_json::Value,
    id: serde_json::Value,
}

#[derive(Debug, Serialize)]
struct RpcResponse {
    jsonrpc: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<RpcError>,
    id: serde_json::Value,
}

#[derive(Debug, Serialize)]
struct RpcError {
    code: i32,
    message: &'static str,
}

impl RpcResponse {
    fn ok(id: serde_json::Value, result: serde_json::Value) -> Self {
        Self { jsonrpc: "2.0", result: Some(result), error: None, id }
    }
    fn err(id: serde_json::Value, code: i32, msg: &'static str) -> Self {
        Self { jsonrpc: "2.0", result: None, error: Some(RpcError { code, message: msg }), id }
    }
    fn internal_error(id: serde_json::Value) -> Self {
        Self::err(id, -32603, "Internal error")
    }
    fn parse_error() -> Self {
        Self::err(serde_json::Value::Null, -32700, "Parse error")
    }
    fn method_not_found(id: serde_json::Value) -> Self {
        Self::err(id, -32601, "Method not found")
    }
}

// ── Dispatch ───────────────────────────────────────────────────────────────

fn dispatch(req: RpcRequest) -> RpcResponse {
    match req.method.as_str() {
        "encrypt" => handle_encrypt(req.id, req.params),
        "decrypt" => handle_decrypt(req.id, req.params),
        "derive_session" => handle_derive_session(req.id, req.params),
        _ => RpcResponse::method_not_found(req.id),
    }
}

#[derive(Deserialize)]
struct EncryptParams {
    /// Base64-encoded 32-byte session key.
    key_b64: String,
    /// Base64-encoded plaintext.
    plaintext_b64: String,
    /// Base64-encoded AAD (may be empty string).
    aad_b64: String,
}

fn handle_encrypt(id: serde_json::Value, params: serde_json::Value) -> RpcResponse {
    let p: EncryptParams = match serde_json::from_value(params) {
        Ok(v) => v,
        Err(_) => return RpcResponse::err(id, -32602, "Invalid params"),
    };
    let key = match b64_to_32(&p.key_b64) {
        Ok(k) => k,
        Err(_) => return RpcResponse::internal_error(id),
    };
    let plaintext = match b64_decode(&p.plaintext_b64) {
        Ok(v) => v,
        Err(_) => return RpcResponse::internal_error(id),
    };
    let aad = b64_decode(&p.aad_b64).unwrap_or_default();

    match seal(&key, &plaintext, &aad) {
        Ok(msg) => {
            let j = serde_json::to_value(&msg).unwrap_or(serde_json::Value::Null);
            RpcResponse::ok(id, j)
        }
        Err(_) => RpcResponse::internal_error(id),
    }
}

#[derive(Deserialize)]
struct DecryptParams {
    key_b64: String,
    message: libnclaw::e2ee::EncryptedMessage,
}

fn handle_decrypt(id: serde_json::Value, params: serde_json::Value) -> RpcResponse {
    let p: DecryptParams = match serde_json::from_value(params) {
        Ok(v) => v,
        Err(_) => return RpcResponse::err(id, -32602, "Invalid params"),
    };
    let key = match b64_to_32(&p.key_b64) {
        Ok(k) => k,
        Err(_) => return RpcResponse::internal_error(id),
    };
    match open(&key, &p.message) {
        Ok(plaintext) => {
            let b64 = b64_encode(&plaintext);
            RpcResponse::ok(id, serde_json::json!({ "plaintext_b64": b64 }))
        }
        // Auth failure — no detail in error message (no oracle)
        Err(E2EEError::DecryptionFailed) => {
            RpcResponse::err(id, -32603, "Internal error")
        }
        Err(_) => RpcResponse::internal_error(id),
    }
}

#[derive(Deserialize)]
struct DeriveSessionParams {
    /// Base64-encoded remote public key (32 bytes).
    remote_pub_b64: String,
}

fn handle_derive_session(id: serde_json::Value, params: serde_json::Value) -> RpcResponse {
    let p: DeriveSessionParams = match serde_json::from_value(params) {
        Ok(v) => v,
        Err(_) => return RpcResponse::err(id, -32602, "Invalid params"),
    };
    let remote_bytes = match b64_decode(&p.remote_pub_b64) {
        Ok(v) => v,
        Err(_) => return RpcResponse::internal_error(id),
    };
    let arr: [u8; 32] = match remote_bytes.try_into() {
        Ok(a) => a,
        Err(_) => return RpcResponse::internal_error(id),
    };
    let remote_pub = x25519_dalek::PublicKey::from(arr);

    // Generate a fresh ephemeral keypair for this derive_session call.
    let (local_priv, local_pub) = generate_keypair();

    match derive_session(local_priv.0, remote_pub, NCLAW_HKDF_INFO) {
        Ok(session) => {
            // Return the local public key so the remote party can derive the same session key.
            // Never log session_key bytes.
            let local_pub_b64 = b64_encode(local_pub.as_bytes());
            let session_key_b64 = b64_encode(&session.session_key);
            RpcResponse::ok(id, serde_json::json!({
                "local_pub_b64": local_pub_b64,
                "session_key_b64": session_key_b64,
            }))
        }
        Err(_) => RpcResponse::internal_error(id),
    }
}

// ── Base64 helpers ─────────────────────────────────────────────────────────

fn b64_encode(bytes: &[u8]) -> String {
    use base64::{engine::general_purpose::STANDARD, Engine};
    STANDARD.encode(bytes)
}

fn b64_decode(s: &str) -> Result<Vec<u8>, ()> {
    use base64::{engine::general_purpose::STANDARD, Engine};
    STANDARD.decode(s).map_err(|_| ())
}

fn b64_to_32(s: &str) -> Result<[u8; 32], ()> {
    let v = b64_decode(s)?;
    v.try_into().map_err(|_| ())
}

// ── Sentry init ────────────────────────────────────────────────────────────

/// Conditionally initialise Sentry if NCLAW_SENTRY_DSN is set.
/// Never crashes if DSN is absent or invalid.
pub fn init_sentry() {
    #[cfg(feature = "sentry-reporting")]
    {
        if let Ok(dsn) = std::env::var("NCLAW_SENTRY_DSN") {
            let _guard = sentry::init(dsn);
            eprintln!("{{\"level\":\"INFO\",\"msg\":\"Sentry initialized\"}}");
        }
    }
}

// ── Main ───────────────────────────────────────────────────────────────────

fn main() {
    init_sentry();

    let socket_path: PathBuf = std::env::var("LIBNCLAW_SOCKET_PATH")
        .unwrap_or_else(|_| "/tmp/libnclaw.sock".to_string())
        .into();

    // Remove stale socket file if present.
    if socket_path.exists() {
        let _ = std::fs::remove_file(&socket_path);
    }

    let listener = UnixListener::bind(&socket_path).expect("Failed to bind Unix socket");
    eprintln!(
        "{{\"level\":\"INFO\",\"msg\":\"libnclaw-server listening\",\"socket\":\"{}\"}}",
        socket_path.display()
    );

    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                std::thread::spawn(move || {
                    let mut reader = BufReader::new(&stream);
                    let mut writer = &stream;
                    let mut line = String::new();

                    loop {
                        line.clear();
                        match reader.read_line(&mut line) {
                            Ok(0) => break, // EOF
                            Ok(_) => {}
                            Err(_) => break,
                        }

                        let response = match serde_json::from_str::<RpcRequest>(line.trim()) {
                            Ok(req) => {
                                if req.jsonrpc != "2.0" {
                                    RpcResponse::parse_error()
                                } else {
                                    dispatch(req)
                                }
                            }
                            Err(_) => RpcResponse::parse_error(),
                        };

                        let mut out = serde_json::to_string(&response).unwrap_or_default();
                        out.push('\n');
                        let _ = writer.write_all(out.as_bytes());
                    }
                });
            }
            Err(e) => {
                eprintln!("{{\"level\":\"ERROR\",\"msg\":\"accept error\",\"error\":\"{e}\"}}");
            }
        }
    }
}

// External crate needed for DeriveSession key type
extern crate x25519_dalek;
