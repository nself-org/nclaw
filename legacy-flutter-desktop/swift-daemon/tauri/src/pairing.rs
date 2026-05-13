use reqwest::Client;
use serde::{Deserialize, Serialize};

#[derive(Serialize)]
struct PairRedeemRequest {
    pair_code: String,
    device_name: String,
    device_type: String,
}

#[derive(Deserialize)]
struct PairRedeemResponse {
    token: String,
}

/// Redeem a pairing code against the companion server.
///
/// Posts the pair code to `/claw/pair/redeem` and receives an auth token.
/// The token is stored in the `NCLAW_AUTH_TOKEN` environment variable
/// for the lifetime of this process. A persistent keyring integration
/// will replace this in a future release.
pub async fn start_pairing(server_url: &str, pair_code: &str) -> Result<String, reqwest::Error> {
    let client = Client::new();
    let hostname = gethostname();

    let body = PairRedeemRequest {
        pair_code: pair_code.to_string(),
        device_name: hostname,
        device_type: current_platform().to_string(),
    };

    let resp = client
        .post(format!("{}/claw/pair/redeem", server_url.trim_end_matches('/')))
        .json(&body)
        .send()
        .await?
        .error_for_status()?
        .json::<PairRedeemResponse>()
        .await?;

    // Store token in env for this process lifetime.
    // A future release will persist this in the OS keyring.
    std::env::set_var("NCLAW_AUTH_TOKEN", &resp.token);

    Ok(resp.token)
}

/// Check whether the companion server is reachable and healthy.
pub async fn check_health(server_url: &str) -> Result<bool, reqwest::Error> {
    let client = Client::new();
    let resp = client
        .get(format!("{}/claw/health", server_url.trim_end_matches('/')))
        .send()
        .await?;

    Ok(resp.status().is_success())
}

fn gethostname() -> String {
    hostname::get()
        .map(|h| h.to_string_lossy().to_string())
        .unwrap_or_else(|_| "unknown".to_string())
}

fn current_platform() -> &'static str {
    if cfg!(target_os = "windows") {
        "windows"
    } else if cfg!(target_os = "linux") {
        "linux"
    } else if cfg!(target_os = "macos") {
        "macos"
    } else {
        "unknown"
    }
}
