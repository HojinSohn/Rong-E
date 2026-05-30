use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use rand::Rng;
use sha2::{Digest, Sha256};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

/// Generate a 64-character random alphanumeric PKCE code verifier (RFC 7636).
fn random_verifier() -> String {
    const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
    let mut rng = rand::thread_rng();
    (0..64)
        .map(|_| CHARSET[rng.gen_range(0..CHARSET.len())] as char)
        .collect()
}

/// SHA-256 hash the verifier then base64url-encode (no padding) → code_challenge.
fn code_challenge(verifier: &str) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()))
}

/// Generate a 16-byte hex state nonce (CSRF protection).
fn random_state() -> String {
    use rand::RngCore;
    let mut bytes = [0u8; 16];
    rand::thread_rng().fill_bytes(&mut bytes);
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

/// Bind a random local listener and build the OpenRouter consent URL.
/// Returns (auth_url, code_verifier, state_nonce, listener).
pub async fn prepare_openrouter_flow(
) -> Result<(String, String, String, tokio::net::TcpListener), String> {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .map_err(|e| format!("Could not start the local authentication server: {}", e))?;
    let port = listener
        .local_addr()
        .map_err(|e| format!("Could not determine the local server port: {}", e))?
        .port();

    let verifier = random_verifier();
    let challenge = code_challenge(&verifier);
    let state = random_state();

    let callback_url = format!("http://localhost:{}", port);
    let url = format!(
        "https://openrouter.ai/auth?callback_url={}&code_challenge={}&code_challenge_method=S256&state={}",
        urlencoding::encode(&callback_url),
        urlencoding::encode(&challenge),
        urlencoding::encode(&state),
    );

    Ok((url, verifier, state, listener))
}

/// Accept the browser redirect, validate the state nonce, exchange the
/// auth code for an OpenRouter API key, and return it.
pub async fn await_openrouter_callback(
    listener: tokio::net::TcpListener,
    verifier: &str,
    expected_state: &str,
) -> Result<String, String> {
    let (mut stream, peer_addr) = listener
        .accept()
        .await
        .map_err(|e| format!("Did not receive a response from the browser: {}", e))?;

    // Only accept loopback connections — prevents other local processes from
    // injecting a fake callback.
    if !peer_addr.ip().is_loopback() {
        return Err("Rejected non-loopback OAuth callback.".to_string());
    }

    let mut buf = vec![0u8; 8192];
    let n = stream
        .read(&mut buf)
        .await
        .map_err(|e| format!("Could not read the browser response: {}", e))?;
    let request = String::from_utf8_lossy(&buf[..n]);

    let path = request
        .lines()
        .next()
        .unwrap_or("")
        .split_whitespace()
        .nth(1)
        .unwrap_or("");
    let query = path.split('?').nth(1).unwrap_or("");

    for param in query.split('&') {
        if let Some(err) = param.strip_prefix("error=") {
            let decoded = urlencoding::decode(err)
                .map(|s| s.to_string())
                .unwrap_or_else(|_| err.to_string());
            let _ = stream.write_all(error_html().as_bytes()).await;
            return Err(format!("Sign-in was cancelled or access was denied: {}", decoded));
        }
    }

    // Validate state nonce (CSRF prevention).
    let returned_state = query
        .split('&')
        .find(|p| p.starts_with("state="))
        .and_then(|p| p.strip_prefix("state="))
        .map(|s| {
            urlencoding::decode(s)
                .map(|d| d.to_string())
                .unwrap_or_else(|_| s.to_string())
        })
        .unwrap_or_default();

    if returned_state != expected_state {
        let _ = stream.write_all(error_html().as_bytes()).await;
        return Err(
            "OAuth state mismatch — possible CSRF attempt. Please try signing in again."
                .to_string(),
        );
    }

    let code = query
        .split('&')
        .find(|p| p.starts_with("code="))
        .and_then(|p| p.strip_prefix("code="))
        .map(|c| {
            urlencoding::decode(c)
                .map(|d| d.to_string())
                .unwrap_or_else(|_| c.to_string())
        })
        .ok_or_else(|| {
            "No authorization code received from OpenRouter. Please try again.".to_string()
        })?;

    let _ = stream.write_all(success_html().as_bytes()).await;
    drop(stream);

    // Exchange { code, code_verifier } → API key.
    let client = reqwest::Client::new();
    let body = serde_json::json!({ "code": code, "code_verifier": verifier });

    let resp = client
        .post("https://openrouter.ai/api/v1/auth/keys")
        .json(&body)
        .send()
        .await
        .map_err(|_| {
            "Could not reach OpenRouter to complete sign-in. Please check your internet connection."
                .to_string()
        })?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body_text = resp.text().await.unwrap_or_default();
        let msg = serde_json::from_str::<serde_json::Value>(&body_text)
            .ok()
            .and_then(|v| {
                v["message"]
                    .as_str()
                    .or_else(|| v["error"].as_str())
                    .map(|s| s.to_string())
            });
        return Err(match msg {
            Some(m) => format!("OpenRouter sign-in failed: {}", m),
            None => format!(
                "OpenRouter sign-in failed (status {}). Please try again.",
                status.as_u16()
            ),
        });
    }

    let json: serde_json::Value = resp.json().await.map_err(|_| {
        "Received an unexpected response from OpenRouter. Please try again.".to_string()
    })?;

    let api_key = json["key"]
        .as_str()
        .ok_or_else(|| "OpenRouter did not return an API key. Please try again.".to_string())?
        .to_string();

    println!("✅ OpenRouter OAuth complete. API key obtained.");
    Ok(api_key)
}

fn success_html() -> &'static str {
    "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n\
     <html><head><meta charset=\"utf-8\">\
     <style>body{font-family:-apple-system,sans-serif;background:#f5f5f7;\
     display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;}\
     .card{background:#fff;border-radius:16px;padding:48px 40px;max-width:420px;\
     text-align:center;box-shadow:0 4px 24px rgba(0,0,0,.08);}\
     h2{margin:0 0 12px;color:#1d1d1f;font-size:22px;font-weight:600;}\
     p{color:#6e6e73;font-size:15px;line-height:1.5;margin:0;}\
     </style></head><body><div class=\"card\">\
     <h2>Connected to OpenRouter</h2>\
     <p>You can close this tab and return to Rong-E.</p>\
     </div></body></html>"
}

fn error_html() -> &'static str {
    "HTTP/1.1 400 Bad Request\r\nContent-Type: text/html\r\n\r\n\
     <html><head><meta charset=\"utf-8\">\
     <style>body{font-family:-apple-system,sans-serif;background:#f5f5f7;\
     display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;}\
     .card{background:#fff;border-radius:16px;padding:48px 40px;max-width:420px;\
     text-align:center;box-shadow:0 4px 24px rgba(0,0,0,.08);}\
     h2{margin:0 0 12px;color:#1d1d1f;font-size:22px;font-weight:600;}\
     p{color:#6e6e73;font-size:15px;line-height:1.5;margin:0;}\
     </style></head><body><div class=\"card\">\
     <h2>Sign-in Cancelled</h2>\
     <p>You can close this tab and try again from the app.</p>\
     </div></body></html>"
}
