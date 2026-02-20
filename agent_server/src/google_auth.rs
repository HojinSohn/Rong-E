use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};

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

    let Some(token_str) = token_str else {
        return Err(
            "No token.json found. Please complete the OAuth flow from the app first.".to_string(),
        );
    };

    let mut token: GoogleToken = serde_json::from_str(&token_str)
        .map_err(|e| format!("Failed to parse token.json: {}", e))?;

    let access_token = token.token.clone().unwrap_or_default();
    let expired = is_token_expired(&token);

    if !access_token.is_empty() && !expired {
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
    let refreshed = refresh_access_token(&client_id, &client_secret, &refresh_token, &token_uri)
        .await
        .map_err(|e| format!("Token refresh failed: {}", e))?;

    // --- 5. Persist updated token ---
    let new_expiry = Utc::now() + Duration::seconds(refreshed.expires_in.unwrap_or(3599) as i64);
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
    if let (Some(id), Some(secret)) = (token.client_id.clone(), token.client_secret.clone()) {
        if !id.is_empty() && !secret.is_empty() {
            let uri = token
                .token_uri
                .clone()
                .unwrap_or_else(|| "https://oauth2.googleapis.com/token".to_string());
            return Ok((id, secret, uri));
        }
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
