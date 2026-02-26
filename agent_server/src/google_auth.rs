use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

/// Mirrors the token.json written by Python's google-auth library.
#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct GoogleToken {
    /// The OAuth2 access token.
    pub token: Option<String>,
    pub refresh_token: Option<String>,
    pub token_uri: Option<String>,
    pub client_id: Option<String>,
    pub client_secret: Option<String>,
    /// ISO-8601 expiry timestamp, e.g. "2024-01-01T00:00:00.000000Z"
    pub expiry: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scopes: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub universe_domain: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub account: Option<String>,
}

/// The top-level shape of credentials.json (installed or web app).
#[derive(Debug, Deserialize)]
struct CredentialsFile {
    installed: Option<ClientConfig>,
    web: Option<ClientConfig>,
}

#[derive(Debug, Deserialize)]
struct ClientConfig {
    client_id: String,
    client_secret: String,
    token_uri: Option<String>,
}

/// Response body from Google's token refresh endpoint.
#[derive(Debug, Deserialize)]
struct RefreshResponse {
    access_token: String,
    expires_in: Option<u64>,
}

/// Response body from the authorization code exchange endpoint.
#[derive(Debug, Deserialize)]
struct TokenExchangeResponse {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: Option<u64>,
    scope: Option<String>,
}

/// Authenticate using the on-disk `token.json` + `credentials.json`.
///
/// Steps (mirrors Python's `AuthManager.authenticate`):
/// 1. Read token.json; if the access token is still valid, return it.
/// 2. If expired, refresh via Google's token endpoint and save the
///    updated token back to disk.
/// 3. If no token.json exists, return an error (browser OAuth cannot
///    be triggered from the server process).
///
/// Returns the valid access token on success, or an error string.
pub async fn authenticate(
    credentials_path: &str,
    token_path: &str,
) -> Result<String, String> {
    // --- 1. Load token.json ---
    let token_str = tokio::fs::read_to_string(token_path).await.ok();

    let mut token = token_str
        .as_deref()
        .map(|s| serde_json::from_str::<GoogleToken>(s)
            .map_err(|e| format!("Failed to parse token.json: {}", e)))
        .transpose()?
        .unwrap_or(GoogleToken {
            token: None,
            refresh_token: None,
            token_uri: None,
            client_id: None,
            client_secret: None,
            expiry: None,
            scopes: None,
            universe_domain: None,
            account: None,
        });

    // --- 1b. Check existing access token ---
    if let Some(access_token) = token.token.clone().filter(|t| !t.is_empty())
        && !is_token_expired(&token)
    {
        println!("✅ Google token is valid.");
        return Ok(access_token);
    }

    println!("🔄 Google token is expired or missing. Attempting refresh…");

    // --- 2. Need a refresh_token ---
    let refresh_token = token
        .refresh_token
        .clone()
        .filter(|r| !r.is_empty())
        .ok_or_else(|| {
            "Token expired and no refresh_token available. Re-authenticate from the app.".to_string()
        })?;

    // --- 3. Resolve client_id / client_secret ---
    let (client_id, client_secret, token_uri) =
        resolve_client_creds(&token, credentials_path).await?;

    // --- 4. Refresh ---
    let refreshed = refresh_access_token(
        &client_id,
        &client_secret,
        &refresh_token,
        &token_uri,
    )
    .await
    .map_err(|e| format!("Token refresh failed: {}", e))?;

    // --- 5. Persist updated token ---
    let new_expiry =
        Utc::now() + Duration::seconds(refreshed.expires_in.unwrap_or(3599) as i64);

    token.token = Some(refreshed.access_token.clone());
    token.expiry = Some(new_expiry.format("%Y-%m-%dT%H:%M:%S%.6fZ").to_string());

    let updated_json = serde_json::to_string_pretty(&token)
        .map_err(|e| format!("Failed to serialize updated token: {}", e))?;

    tokio::fs::write(token_path, updated_json)
        .await
        .map_err(|e| format!("Failed to save refreshed token.json: {}", e))?;

    println!("✅ Google token refreshed and saved.");
    Ok(refreshed.access_token)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns `true` if the token is expired (or within 60 s of expiry).
fn is_token_expired(token: &GoogleToken) -> bool {
    let Some(ref expiry_str) = token.expiry else {
        return true;
    };

    // Try RFC-3339 first, then the no-fractional-seconds variant.
    let parsed: Option<DateTime<Utc>> = DateTime::parse_from_rfc3339(expiry_str)
        .map(|dt| dt.with_timezone(&Utc))
        .ok()
        .or_else(|| {
            chrono::NaiveDateTime::parse_from_str(expiry_str, "%Y-%m-%dT%H:%M:%SZ")
                .map(|ndt| ndt.and_utc())
                .ok()
        });

    match parsed {
        Some(expiry) => expiry <= Utc::now() + Duration::seconds(60),
        None => true, // Unparseable → treat as expired
    }
}

/// Extracts client_id / client_secret / token_uri from the token itself
/// (Python stores them there) or falls back to credentials.json.
async fn resolve_client_creds(
    token: &GoogleToken,
    credentials_path: &str,
) -> Result<(String, String, String), String> {
    // Prefer values embedded in token.json (Python writes them there)
    if let (Some(id), Some(secret)) = (token.client_id.clone(), token.client_secret.clone())
        && !id.is_empty() && !secret.is_empty()
    {
        let uri = token
            .token_uri
            .clone()
            .unwrap_or_else(|| "https://oauth2.googleapis.com/token".to_string());
        return Ok((id, secret, uri));
    }

    // Fall back to credentials.json
    let creds_str = tokio::fs::read_to_string(credentials_path)
        .await
        .map_err(|e| format!("Failed to read credentials.json: {}", e))?;
    let creds: CredentialsFile = serde_json::from_str(&creds_str)
        .map_err(|e| format!("Failed to parse credentials.json: {}", e))?;

    let cfg = creds
        .installed
        .or(creds.web)
        .ok_or_else(|| "credentials.json has no 'installed' or 'web' section.".to_string())?;

    let uri = cfg
        .token_uri
        .unwrap_or_else(|| "https://oauth2.googleapis.com/token".to_string());

    Ok((cfg.client_id, cfg.client_secret, uri))
}

// ---------------------------------------------------------------------------
// Full OAuth2 authorization-code flow (for first-time or re-auth)
// ---------------------------------------------------------------------------

/// Binds a local TCP listener, builds the Google consent URL, and returns
/// both so the caller can send the URL to the UI and then await the callback.
pub async fn prepare_oauth_flow(
    credentials_path: &str,
) -> Result<(String, tokio::net::TcpListener), String> {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .map_err(|e| format!("Failed to bind OAuth listener: {}", e))?;
    let port = listener
        .local_addr()
        .map_err(|e| format!("Failed to get local port: {}", e))?
        .port();

    let creds_str = tokio::fs::read_to_string(credentials_path)
        .await
        .map_err(|e| format!("Failed to read credentials.json: {}", e))?;
    let creds: CredentialsFile = serde_json::from_str(&creds_str)
        .map_err(|e| format!("Failed to parse credentials.json: {}", e))?;
    let cfg = creds
        .installed
        .or(creds.web)
        .ok_or_else(|| "credentials.json has no 'installed' or 'web' section.".to_string())?;

    let redirect_uri = format!("http://localhost:{}", port);
    let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/calendar",
        "https://www.googleapis.com/auth/spreadsheets",
    ]
    .join(" ");

    let url = format!(
        "https://accounts.google.com/o/oauth2/auth\
         ?client_id={}\
         &redirect_uri={}\
         &response_type=code\
         &scope={}\
         &access_type=offline\
         &prompt=consent",
        urlencoding::encode(&cfg.client_id),
        urlencoding::encode(&redirect_uri),
        urlencoding::encode(&scopes),
    );

    Ok((url, listener))
}

/// Accepts one HTTP redirect from the browser, exchanges the authorization
/// code for tokens, writes `token.json`, and returns the access token.
pub async fn await_oauth_callback(
    listener: tokio::net::TcpListener,
    credentials_path: &str,
    token_path: &str,
) -> Result<String, String> {
    let port = listener
        .local_addr()
        .map_err(|e| format!("Failed to get port: {}", e))?
        .port();

    // Accept exactly one connection (the browser redirect)
    let (mut stream, _) = listener
        .accept()
        .await
        .map_err(|e| format!("Failed to accept OAuth callback: {}", e))?;

    // Read the HTTP request
    let mut buf = vec![0u8; 8192];
    let n = stream
        .read(&mut buf)
        .await
        .map_err(|e| format!("Failed to read callback request: {}", e))?;
    let request = String::from_utf8_lossy(&buf[..n]);

    // First line: "GET /?code=XXX&scope=... HTTP/1.1"
    let path = request
        .lines()
        .next()
        .unwrap_or("")
        .split_whitespace()
        .nth(1)
        .unwrap_or("");
    let query = path.split('?').nth(1).unwrap_or("");

    // Check for an error param before looking for the code
    for param in query.split('&') {
        if let Some(err) = param.strip_prefix("error=") {
            let decoded = urlencoding::decode(err)
                .map(|s| s.to_string())
                .unwrap_or_else(|_| err.to_string());
            let _ = stream
                .write_all(
                    b"HTTP/1.1 400 Bad Request\r\nContent-Type: text/html\r\n\r\n\
                      <html><body><h2>Authentication cancelled or denied.</h2>\
                      <p>You can close this tab.</p></body></html>",
                )
                .await;
            return Err(format!("OAuth error: {}", decoded));
        }
    }

    // Extract the authorization code
    let code = query
        .split('&')
        .find(|p| p.starts_with("code="))
        .and_then(|p| p.strip_prefix("code="))
        .map(|c| {
            urlencoding::decode(c)
                .map(|s| s.to_string())
                .unwrap_or_else(|_| c.to_string())
        })
        .ok_or_else(|| "No authorization code in callback URL".to_string())?;

    // Respond to the browser immediately
    let success_html = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n\
              <html><body style=\"font-family:sans-serif;text-align:center;padding:60px\">\
              <h2>\u{2705} Authentication Successful!</h2>\
              <p>You can close this tab and return to Rong-E.</p>\
              </body></html>";
    let _ = stream.write_all(success_html.as_bytes()).await;
    drop(stream);

    // Load client credentials for the exchange
    let creds_str = tokio::fs::read_to_string(credentials_path)
        .await
        .map_err(|e| format!("Failed to read credentials.json: {}", e))?;
    let creds: CredentialsFile = serde_json::from_str(&creds_str)
        .map_err(|e| format!("Failed to parse credentials.json: {}", e))?;
    let cfg = creds
        .installed
        .or(creds.web)
        .ok_or_else(|| "credentials.json has no 'installed' or 'web' section.".to_string())?;

    let token_uri = cfg
        .token_uri
        .clone()
        .unwrap_or_else(|| "https://oauth2.googleapis.com/token".to_string());
    let redirect_uri = format!("http://localhost:{}", port);

    // Exchange code → tokens
    let client = reqwest::Client::new();
    let params = [
        ("code", code.as_str()),
        ("client_id", cfg.client_id.as_str()),
        ("client_secret", cfg.client_secret.as_str()),
        ("redirect_uri", redirect_uri.as_str()),
        ("grant_type", "authorization_code"),
    ];
    let resp = client
        .post(&token_uri)
        .form(&params)
        .send()
        .await
        .map_err(|e| format!("Token exchange request failed: {}", e))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(format!("Token exchange failed {}: {}", status, body));
    }

    let token_resp: TokenExchangeResponse = resp
        .json()
        .await
        .map_err(|e| format!("Failed to parse token response: {}", e))?;

    // Persist the new token.json
    let expiry = Utc::now() + Duration::seconds(token_resp.expires_in.unwrap_or(3599) as i64);
    let new_token = GoogleToken {
        token: Some(token_resp.access_token.clone()),
        refresh_token: token_resp.refresh_token,
        token_uri: Some(token_uri),
        client_id: Some(cfg.client_id),
        client_secret: Some(cfg.client_secret),
        expiry: Some(expiry.format("%Y-%m-%dT%H:%M:%S%.6fZ").to_string()),
        scopes: token_resp.scope.map(serde_json::Value::String),
        universe_domain: Some("googleapis.com".to_string()),
        account: None,
    };

    let json_str = serde_json::to_string_pretty(&new_token)
        .map_err(|e| format!("Failed to serialize token: {}", e))?;
    tokio::fs::write(token_path, &json_str)
        .await
        .map_err(|e| format!("Failed to write token.json: {}", e))?;

    println!("✅ OAuth flow complete. Token saved to {}", token_path);
    Ok(token_resp.access_token)
}

/// Sends a POST to Google's token endpoint to exchange a refresh_token
/// for a new access_token.
async fn refresh_access_token(
    client_id: &str,
    client_secret: &str,
    refresh_token: &str,
    token_uri: &str,
) -> Result<RefreshResponse, String> {
    let client = reqwest::Client::new();
    let params = [
        ("client_id", client_id),
        ("client_secret", client_secret),
        ("refresh_token", refresh_token),
        ("grant_type", "refresh_token"),
    ];

    let resp: reqwest::Response = client
        .post(token_uri)
        .form(&params)
        .send()
        .await
        .map_err(|e| format!("HTTP request to token endpoint failed: {}", e))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body: String = resp.text().await.unwrap_or_default();
        return Err(format!("Token endpoint returned {}: {}", status, body));
    }

    resp.json::<RefreshResponse>()
        .await
        .map_err(|e| format!("Failed to deserialize refresh response: {}", e))
}
