use base64::{engine::general_purpose, Engine as _};
use chrono::{Duration, Utc};
use urlencoding::encode as urlencode;
use futures::future;
use rig::completion::ToolDefinition;
use rig::tool::Tool;
use serde::{Deserialize, Serialize};
use thiserror::Error;

// ── Error ──

#[derive(Debug, Error)]
#[error("{0}")]
pub struct GoogleToolError(pub String);

impl From<String> for GoogleToolError {
    fn from(s: String) -> Self {
        GoogleToolError(s)
    }
}

// ─────────────────────────────────────────────
// Internal HTTP helpers
// ─────────────────────────────────────────────

/// Send a request and parse the JSON response body.
async fn send_json(req: reqwest::RequestBuilder) -> Result<serde_json::Value, String> {
    let resp: reqwest::Response = req
        .send()
        .await
        .map_err(|e| format!("HTTP error: {}", e))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body: String = resp.text().await.unwrap_or_default();
        return Err(format!("Google API {} – {}", status, body));
    }

    resp.json::<serde_json::Value>()
        .await
        .map_err(|e| format!("JSON parse error: {}", e))
}

/// Send a request that returns no body (e.g. DELETE 204).
async fn send_empty(req: reqwest::RequestBuilder) -> Result<(), String> {
    let resp: reqwest::Response = req
        .send()
        .await
        .map_err(|e| format!("HTTP error: {}", e))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body: String = resp.text().await.unwrap_or_default();
        return Err(format!("Google API {} – {}", status, body));
    }

    Ok(())
}

// ─────────────────────────────────────────────
// Gmail body decoding helpers
// ─────────────────────────────────────────────

/// Decode base64url-encoded Gmail body data into UTF-8 text.
fn decode_gmail_body(data: &str) -> String {
    let fixed = data.replace('-', "+").replace('_', "/");
    match general_purpose::STANDARD_NO_PAD.decode(&fixed) {
        Ok(bytes) => String::from_utf8_lossy(&bytes).to_string(),
        Err(_) => "[Could not decode body]".to_string(),
    }
}

/// Recursively extract plain text from a Gmail message payload (handles multipart).
fn extract_text(payload: &serde_json::Value) -> String {
    // Direct body data
    if let Some(data) = payload["body"]["data"].as_str()
        && !data.is_empty()
    {
        return decode_gmail_body(data);
    }

    if let Some(parts) = payload["parts"].as_array() {
        // Prefer text/plain
        for part in parts {
            if part["mimeType"].as_str() == Some("text/plain")
                && let Some(data) = part["body"]["data"].as_str()
                && !data.is_empty()
            {
                return decode_gmail_body(data);
            }
        }
        // Fall back to text/html
        for part in parts {
            if part["mimeType"].as_str() == Some("text/html")
                && let Some(data) = part["body"]["data"].as_str()
                && !data.is_empty()
            {
                return format!("[HTML] {}", decode_gmail_body(data));
            }
        }
        // Recurse into nested multipart
        for part in parts {
            if part["mimeType"]
                .as_str()
                .unwrap_or("")
                .starts_with("multipart/")
            {
                let text = extract_text(part);
                if text != "[No text content]" {
                    return text;
                }
            }
        }
    }

    "[No text content]".to_string()
}

/// Look up a named header value from a Gmail headers array.
fn header(headers: &serde_json::Value, name: &str) -> String {
    headers
        .as_array()
        .and_then(|arr| {
            arr.iter().find(|h| {
                h["name"]
                    .as_str()
                    .map(|n| n.eq_ignore_ascii_case(name))
                    == Some(true)
            })
        })
        .and_then(|h| h["value"].as_str())
        .unwrap_or("")
        .to_string()
}

// ─────────────────────────────────────────────
// Gmail – SearchGmail
// ─────────────────────────────────────────────

#[derive(Deserialize, Serialize, Clone)]
pub struct SearchGmail {
    #[serde(skip)]
    pub access_token: String,
}

impl SearchGmail {
    pub fn new(access_token: String) -> Self {
        Self { access_token }
    }
}

#[derive(Deserialize)]
pub struct SearchGmailArgs {
    query: String,
    max_results: Option<u32>,
}

impl Tool for SearchGmail {
    const NAME: &'static str = "search_gmail";
    type Args = SearchGmailArgs;
    type Output = String;
    type Error = GoogleToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "search_gmail".to_string(),
            description: "Search Gmail messages using Gmail query syntax (e.g. 'from:alice subject:meeting is:unread'). Returns a list of matching messages with ID, sender, date, subject, and a short snippet.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Gmail search query (same syntax as the Gmail search bar)"
                    },
                    "max_results": {
                        "type": "integer",
                        "description": "Max messages to return (default 10, max 50)"
                    }
                },
                "required": ["query"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let max = args.max_results.unwrap_or(10).min(50);
        let client = reqwest::Client::new();

        // 1. List matching message IDs
        let list = send_json(
            client
                .get(format!(
                    "https://gmail.googleapis.com/gmail/v1/users/me/messages?q={}&maxResults={}",
                    urlencode(&args.query),
                    max
                ))
                .bearer_auth(&self.access_token),
        )
        .await
        .map_err(GoogleToolError)?;

        let ids: Vec<String> = match list["messages"].as_array() {
            Some(m) if !m.is_empty() => m
                .iter()
                .filter_map(|v| v["id"].as_str().map(|s| s.to_string()))
                .collect(),
            _ => return Ok("No messages found.".to_string()),
        };

        // 2. Fetch metadata for all IDs in parallel
        let fetches = ids.iter().map(|id| {
            let token = self.access_token.clone();
            let id = id.clone();
            let c = client.clone();
            async move {
                send_json(
                    c.get(format!(
                        "https://gmail.googleapis.com/gmail/v1/users/me/messages/{}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date",
                        id
                    ))
                    .bearer_auth(&token),
                )
                .await
            }
        });

        let results = future::join_all(fetches).await;

        let mut lines: Vec<String> = Vec::new();
        for (id, res) in ids.iter().zip(results.iter()) {
            match res {
                Ok(msg) => {
                    let hdrs = &msg["payload"]["headers"];
                    let subject = header(hdrs, "Subject");
                    let from = header(hdrs, "From");
                    let date = header(hdrs, "Date");
                    let snippet = msg["snippet"].as_str().unwrap_or("").to_string();
                    lines.push(format!(
                        "ID: {id}\nFrom: {from}\nDate: {date}\nSubject: {subject}\nSnippet: {snippet}"
                    ));
                }
                Err(e) => lines.push(format!("ID: {id} [Error: {e}]")),
            }
        }

        Ok(lines.join("\n\n---\n\n"))
    }
}

// ─────────────────────────────────────────────
// Gmail – GetGmailMessage
// ─────────────────────────────────────────────

#[derive(Deserialize, Serialize, Clone)]
pub struct GetGmailMessage {
    #[serde(skip)]
    pub access_token: String,
}

impl GetGmailMessage {
    pub fn new(access_token: String) -> Self {
        Self { access_token }
    }
}

#[derive(Deserialize)]
pub struct GetGmailMessageArgs {
    message_id: String,
}

impl Tool for GetGmailMessage {
    const NAME: &'static str = "get_gmail_message";
    type Args = GetGmailMessageArgs;
    type Output = String;
    type Error = GoogleToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "get_gmail_message".to_string(),
            description: "Fetch the full content of a Gmail message by its ID. Returns From, To, Subject, Date headers and the decoded message body.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "message_id": {
                        "type": "string",
                        "description": "Gmail message ID (from search_gmail results)"
                    }
                },
                "required": ["message_id"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let msg = send_json(
            reqwest::Client::new()
                .get(format!(
                    "https://gmail.googleapis.com/gmail/v1/users/me/messages/{}?format=full",
                    args.message_id
                ))
                .bearer_auth(&self.access_token),
        )
        .await
        .map_err(GoogleToolError)?;

        let hdrs = &msg["payload"]["headers"];
        let subject = header(hdrs, "Subject");
        let from = header(hdrs, "From");
        let to = header(hdrs, "To");
        let date = header(hdrs, "Date");
        let body = extract_text(&msg["payload"]);

        Ok(format!(
            "From: {from}\nTo: {to}\nDate: {date}\nSubject: {subject}\n\n{body}"
        ))
    }
}

// ─────────────────────────────────────────────
// Gmail – GetGmailThread
// ─────────────────────────────────────────────

#[derive(Deserialize, Serialize, Clone)]
pub struct GetGmailThread {
    #[serde(skip)]
    pub access_token: String,
}

impl GetGmailThread {
    pub fn new(access_token: String) -> Self {
        Self { access_token }
    }
}

#[derive(Deserialize)]
pub struct GetGmailThreadArgs {
    thread_id: String,
}

impl Tool for GetGmailThread {
    const NAME: &'static str = "get_gmail_thread";
    type Args = GetGmailThreadArgs;
    type Output = String;
    type Error = GoogleToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "get_gmail_thread".to_string(),
            description: "Fetch all messages in a Gmail thread. Returns each message's headers and body in chronological order.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "thread_id": {
                        "type": "string",
                        "description": "Gmail thread ID"
                    }
                },
                "required": ["thread_id"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let thread = send_json(
            reqwest::Client::new()
                .get(format!(
                    "https://gmail.googleapis.com/gmail/v1/users/me/threads/{}?format=full",
                    args.thread_id
                ))
                .bearer_auth(&self.access_token),
        )
        .await
        .map_err(GoogleToolError)?;

        let messages = match thread["messages"].as_array() {
            Some(m) if !m.is_empty() => m,
            _ => return Ok("No messages in thread.".to_string()),
        };

        let parts: Vec<String> = messages
            .iter()
            .enumerate()
            .map(|(i, msg)| {
                let hdrs = &msg["payload"]["headers"];
                let subject = header(hdrs, "Subject");
                let from = header(hdrs, "From");
                let date = header(hdrs, "Date");
                let body = extract_text(&msg["payload"]);
                format!(
                    "--- Message {} ---\nFrom: {from}\nDate: {date}\nSubject: {subject}\n\n{body}",
                    i + 1
                )
            })
            .collect();

        Ok(parts.join("\n\n"))
    }
}

// ─────────────────────────────────────────────
// Calendar – ListCalendarEvents
// ─────────────────────────────────────────────

#[derive(Deserialize, Serialize, Clone)]
pub struct ListCalendarEvents {
    #[serde(skip)]
    pub access_token: String,
}

impl ListCalendarEvents {
    pub fn new(access_token: String) -> Self {
        Self { access_token }
    }
}

#[derive(Deserialize)]
pub struct ListCalendarEventsArgs {
    /// RFC3339 start; defaults to now.
    time_min: Option<String>,
    /// RFC3339 end; defaults to 7 days from now.
    time_max: Option<String>,
    max_results: Option<u32>,
    /// Defaults to "primary".
    calendar_id: Option<String>,
}

impl Tool for ListCalendarEvents {
    const NAME: &'static str = "list_calendar_events";
    type Args = ListCalendarEventsArgs;
    type Output = String;
    type Error = GoogleToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "list_calendar_events".to_string(),
            description: "List Google Calendar events in a given time range. Defaults to the next 7 days if no range is specified.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "time_min": {
                        "type": "string",
                        "description": "Start of time range in RFC3339 (e.g. '2024-01-15T00:00:00Z'). Defaults to now."
                    },
                    "time_max": {
                        "type": "string",
                        "description": "End of time range in RFC3339. Defaults to 7 days from now."
                    },
                    "max_results": {
                        "type": "integer",
                        "description": "Maximum events to return (default 20)"
                    },
                    "calendar_id": {
                        "type": "string",
                        "description": "Calendar ID (default: 'primary')"
                    }
                },
                "required": []
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let now = Utc::now();
        let time_min = args
            .time_min
            .unwrap_or_else(|| now.format("%Y-%m-%dT%H:%M:%SZ").to_string());
        let time_max = args.time_max.unwrap_or_else(|| {
            (now + Duration::days(7))
                .format("%Y-%m-%dT%H:%M:%SZ")
                .to_string()
        });
        let max = args.max_results.unwrap_or(20).min(100).to_string();
        let calendar_id = args
            .calendar_id
            .unwrap_or_else(|| "primary".to_string());

        let resp = send_json(
            reqwest::Client::new()
                .get(format!(
                    "https://www.googleapis.com/calendar/v3/calendars/{}/events?timeMin={}&timeMax={}&maxResults={}&orderBy=startTime&singleEvents=true",
                    urlencode(&calendar_id),
                    urlencode(&time_min),
                    urlencode(&time_max),
                    max
                ))
                .bearer_auth(&self.access_token),
        )
        .await
        .map_err(GoogleToolError)?;

        let items = match resp["items"].as_array() {
            Some(i) if !i.is_empty() => i,
            _ => return Ok("No events found in the specified time range.".to_string()),
        };

        let entries: Vec<String> = items
            .iter()
            .map(|ev| {
                let id = ev["id"].as_str().unwrap_or("?");
                let title = ev["summary"].as_str().unwrap_or("(No title)");
                let start = ev["start"]["dateTime"]
                    .as_str()
                    .or_else(|| ev["start"]["date"].as_str())
                    .unwrap_or("?");
                let end = ev["end"]["dateTime"]
                    .as_str()
                    .or_else(|| ev["end"]["date"].as_str())
                    .unwrap_or("?");
                let location = ev["location"].as_str().unwrap_or("");
                let description = ev["description"].as_str().unwrap_or("");

                let mut entry =
                    format!("ID: {id}\nTitle: {title}\nStart: {start}\nEnd: {end}");
                if !location.is_empty() {
                    entry.push_str(&format!("\nLocation: {location}"));
                }
                if !description.is_empty() {
                    let preview = if description.len() > 200 {
                        format!("{}…", &description[..200])
                    } else {
                        description.to_string()
                    };
                    entry.push_str(&format!("\nDescription: {preview}"));
                }
                entry
            })
            .collect();

        Ok(entries.join("\n\n---\n\n"))
    }
}

// ─────────────────────────────────────────────
// Calendar – CreateCalendarEvent
// ─────────────────────────────────────────────

#[derive(Deserialize, Serialize, Clone)]
pub struct CreateCalendarEvent {
    #[serde(skip)]
    pub access_token: String,
}

impl CreateCalendarEvent {
    pub fn new(access_token: String) -> Self {
        Self { access_token }
    }
}

#[derive(Deserialize)]
pub struct CreateCalendarEventArgs {
    summary: String,
    start_datetime: String,
    end_datetime: String,
    description: Option<String>,
    location: Option<String>,
    attendees: Option<Vec<String>>,
    timezone: Option<String>,
    calendar_id: Option<String>,
}

impl Tool for CreateCalendarEvent {
    const NAME: &'static str = "create_calendar_event";
    type Args = CreateCalendarEventArgs;
    type Output = String;
    type Error = GoogleToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "create_calendar_event".to_string(),
            description: "Create a new Google Calendar event.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "summary": { "type": "string", "description": "Event title" },
                    "start_datetime": { "type": "string", "description": "Start time in RFC3339 (e.g. '2024-01-15T10:00:00-05:00')" },
                    "end_datetime":   { "type": "string", "description": "End time in RFC3339" },
                    "description":    { "type": "string", "description": "Event description / notes" },
                    "location":       { "type": "string", "description": "Event location" },
                    "attendees":      { "type": "array", "items": {"type": "string"}, "description": "List of attendee email addresses" },
                    "timezone":       { "type": "string", "description": "IANA timezone (e.g. 'America/New_York'). Defaults to UTC." },
                    "calendar_id":    { "type": "string", "description": "Calendar ID (default: 'primary')" }
                },
                "required": ["summary", "start_datetime", "end_datetime"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let tz = args.timezone.as_deref().unwrap_or("UTC");
        let calendar_id = args
            .calendar_id
            .unwrap_or_else(|| "primary".to_string());

        let mut body = serde_json::json!({
            "summary": args.summary,
            "start": { "dateTime": args.start_datetime, "timeZone": tz },
            "end":   { "dateTime": args.end_datetime,   "timeZone": tz }
        });

        if let Some(d) = args.description {
            body["description"] = serde_json::Value::String(d);
        }
        if let Some(l) = args.location {
            body["location"] = serde_json::Value::String(l);
        }
        if let Some(emails) = args.attendees {
            body["attendees"] = serde_json::json!(
                emails
                    .iter()
                    .map(|e| serde_json::json!({"email": e}))
                    .collect::<Vec<_>>()
            );
        }

        let resp = send_json(
            reqwest::Client::new()
                .post(format!(
                    "https://www.googleapis.com/calendar/v3/calendars/{}/events",
                    calendar_id
                ))
                .bearer_auth(&self.access_token)
                .json(&body),
        )
        .await
        .map_err(GoogleToolError)?;

        let id = resp["id"].as_str().unwrap_or("?");
        let link = resp["htmlLink"].as_str().unwrap_or("");
        Ok(format!("✅ Event created.\nID: {id}\nLink: {link}"))
    }
}

// ─────────────────────────────────────────────
// Calendar – UpdateCalendarEvent
// ─────────────────────────────────────────────

#[derive(Deserialize, Serialize, Clone)]
pub struct UpdateCalendarEvent {
    #[serde(skip)]
    pub access_token: String,
}

impl UpdateCalendarEvent {
    pub fn new(access_token: String) -> Self {
        Self { access_token }
    }
}

#[derive(Deserialize)]
pub struct UpdateCalendarEventArgs {
    event_id: String,
    summary: Option<String>,
    description: Option<String>,
    location: Option<String>,
    start_datetime: Option<String>,
    end_datetime: Option<String>,
    timezone: Option<String>,
    calendar_id: Option<String>,
}

impl Tool for UpdateCalendarEvent {
    const NAME: &'static str = "update_calendar_event";
    type Args = UpdateCalendarEventArgs;
    type Output = String;
    type Error = GoogleToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "update_calendar_event".to_string(),
            description: "Update an existing Google Calendar event. Only provide the fields you want to change.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "event_id":       { "type": "string", "description": "Event ID to update" },
                    "summary":        { "type": "string", "description": "New title" },
                    "description":    { "type": "string", "description": "New description" },
                    "location":       { "type": "string", "description": "New location" },
                    "start_datetime": { "type": "string", "description": "New start time in RFC3339" },
                    "end_datetime":   { "type": "string", "description": "New end time in RFC3339" },
                    "timezone":       { "type": "string", "description": "IANA timezone for start/end" },
                    "calendar_id":    { "type": "string", "description": "Calendar ID (default: 'primary')" }
                },
                "required": ["event_id"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let tz = args.timezone.as_deref().unwrap_or("UTC");
        let calendar_id = args
            .calendar_id
            .unwrap_or_else(|| "primary".to_string());

        let mut patch = serde_json::json!({});

        if let Some(s) = args.summary {
            patch["summary"] = serde_json::Value::String(s);
        }
        if let Some(d) = args.description {
            patch["description"] = serde_json::Value::String(d);
        }
        if let Some(l) = args.location {
            patch["location"] = serde_json::Value::String(l);
        }
        if let Some(start) = args.start_datetime {
            patch["start"] = serde_json::json!({ "dateTime": start, "timeZone": tz });
        }
        if let Some(end) = args.end_datetime {
            patch["end"] = serde_json::json!({ "dateTime": end, "timeZone": tz });
        }

        let resp = send_json(
            reqwest::Client::new()
                .patch(format!(
                    "https://www.googleapis.com/calendar/v3/calendars/{}/events/{}",
                    calendar_id, args.event_id
                ))
                .bearer_auth(&self.access_token)
                .json(&patch),
        )
        .await
        .map_err(GoogleToolError)?;

        let id = resp["id"].as_str().unwrap_or("?");
        let link = resp["htmlLink"].as_str().unwrap_or("");
        Ok(format!("✅ Event updated.\nID: {id}\nLink: {link}"))
    }
}

// ─────────────────────────────────────────────
// Calendar – DeleteCalendarEvent
// ─────────────────────────────────────────────

#[derive(Deserialize, Serialize, Clone)]
pub struct DeleteCalendarEvent {
    #[serde(skip)]
    pub access_token: String,
}

impl DeleteCalendarEvent {
    pub fn new(access_token: String) -> Self {
        Self { access_token }
    }
}

#[derive(Deserialize)]
pub struct DeleteCalendarEventArgs {
    event_id: String,
    calendar_id: Option<String>,
}

impl Tool for DeleteCalendarEvent {
    const NAME: &'static str = "delete_calendar_event";
    type Args = DeleteCalendarEventArgs;
    type Output = String;
    type Error = GoogleToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "delete_calendar_event".to_string(),
            description: "Delete a Google Calendar event by its ID.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "event_id":    { "type": "string", "description": "Event ID to delete" },
                    "calendar_id": { "type": "string", "description": "Calendar ID (default: 'primary')" }
                },
                "required": ["event_id"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let calendar_id = args
            .calendar_id
            .unwrap_or_else(|| "primary".to_string());

        send_empty(
            reqwest::Client::new()
                .delete(format!(
                    "https://www.googleapis.com/calendar/v3/calendars/{}/events/{}",
                    calendar_id, args.event_id
                ))
                .bearer_auth(&self.access_token),
        )
        .await
        .map_err(GoogleToolError)?;

        Ok(format!("✅ Event {} deleted.", args.event_id))
    }
}

// ─────────────────────────────────────────────
// Google Sheets – ManageSpreadsheet
// ─────────────────────────────────────────────

#[derive(Deserialize, Serialize, Clone)]
pub struct ManageSpreadsheet {
    #[serde(skip)]
    pub access_token: String,
}

impl ManageSpreadsheet {
    pub fn new(access_token: String) -> Self {
        Self { access_token }
    }
}

#[derive(Deserialize)]
pub struct ManageSpreadsheetArgs {
    /// "read" | "append" | "update" | "create"
    action: String,
    /// Cell range (e.g. "Sheet1!A1:D10"). For "create", used as the new spreadsheet title.
    range_name: String,
    /// Required for read / append / update. Not needed for create.
    spreadsheet_id: Option<String>,
    /// JSON array-of-arrays for append / update (e.g. `[["Alice", 30], ["Bob", 25]]`).
    values_json: Option<String>,
}

impl Tool for ManageSpreadsheet {
    const NAME: &'static str = "manage_spreadsheet";
    type Args = ManageSpreadsheetArgs;
    type Output = String;
    type Error = GoogleToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "manage_spreadsheet".to_string(),
            description: "Read, append, update, or create a Google Sheets spreadsheet.\n\
                - action='read':   read cells from spreadsheet_id at range_name\n\
                - action='append': add rows to spreadsheet_id at range_name (requires values_json)\n\
                - action='update': overwrite cells in spreadsheet_id at range_name (requires values_json)\n\
                - action='create': create a new spreadsheet titled range_name (spreadsheet_id not needed)".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "action": {
                        "type": "string",
                        "enum": ["read", "append", "update", "create"],
                        "description": "Operation to perform"
                    },
                    "range_name": {
                        "type": "string",
                        "description": "Cell range like 'Sheet1!A1:D10', or new spreadsheet title for 'create'"
                    },
                    "spreadsheet_id": {
                        "type": "string",
                        "description": "Google Sheets spreadsheet ID (required for read/append/update)"
                    },
                    "values_json": {
                        "type": "string",
                        "description": "JSON array-of-arrays of values to write, e.g. [[\"Name\",\"Age\"],[\"Alice\",30]]"
                    }
                },
                "required": ["action", "range_name"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        match args.action.as_str() {
            "read" => {
                let sid = args
                    .spreadsheet_id
                    .as_deref()
                    .filter(|s| !s.is_empty())
                    .ok_or_else(|| GoogleToolError("spreadsheet_id is required for read".into()))?;

                let resp = send_json(
                    reqwest::Client::new()
                        .get(format!(
                            "https://sheets.googleapis.com/v4/spreadsheets/{}/values/{}",
                            sid,
                            urlencode(&args.range_name)
                        ))
                        .bearer_auth(&self.access_token),
                )
                .await
                .map_err(GoogleToolError)?;

                let rows = resp["values"].as_array().cloned().unwrap_or_default();
                Ok(format!(
                    "✅ Read {} row(s) from {}.\nData: {}",
                    rows.len(),
                    args.range_name,
                    serde_json::to_string(&rows).unwrap_or_default()
                ))
            }

            "append" => {
                let sid = args
                    .spreadsheet_id
                    .as_deref()
                    .filter(|s| !s.is_empty())
                    .ok_or_else(|| GoogleToolError("spreadsheet_id is required for append".into()))?;
                let values = parse_values_json(args.values_json.as_deref())?;

                let body = serde_json::json!({ "values": values });
                let resp = send_json(
                    reqwest::Client::new()
                        .post(format!(
                            "https://sheets.googleapis.com/v4/spreadsheets/{}/values/{}:append?valueInputOption=USER_ENTERED",
                            sid,
                            urlencode(&args.range_name)
                        ))
                        .bearer_auth(&self.access_token)
                        .json(&body),
                )
                .await
                .map_err(GoogleToolError)?;

                let updated_rows = resp["updates"]["updatedRows"]
                    .as_u64()
                    .unwrap_or(0);
                Ok(format!("✅ Appended {} row(s) to {}.", updated_rows, args.range_name))
            }

            "update" => {
                let sid = args
                    .spreadsheet_id
                    .as_deref()
                    .filter(|s| !s.is_empty())
                    .ok_or_else(|| GoogleToolError("spreadsheet_id is required for update".into()))?;
                let values = parse_values_json(args.values_json.as_deref())?;

                let body = serde_json::json!({ "values": values });
                let resp = send_json(
                    reqwest::Client::new()
                        .put(format!(
                            "https://sheets.googleapis.com/v4/spreadsheets/{}/values/{}?valueInputOption=USER_ENTERED",
                            sid,
                            urlencode(&args.range_name)
                        ))
                        .bearer_auth(&self.access_token)
                        .json(&body),
                )
                .await
                .map_err(GoogleToolError)?;

                let updated_cells = resp["updatedCells"].as_u64().unwrap_or(0);
                Ok(format!("✅ Updated {} cell(s) in {}.", updated_cells, args.range_name))
            }

            "create" => {
                let body = serde_json::json!({
                    "properties": { "title": args.range_name }
                });
                let resp = send_json(
                    reqwest::Client::new()
                        .post("https://sheets.googleapis.com/v4/spreadsheets")
                        .bearer_auth(&self.access_token)
                        .json(&body),
                )
                .await
                .map_err(GoogleToolError)?;

                let new_id = resp["spreadsheetId"].as_str().unwrap_or("?");
                let link = resp["spreadsheetUrl"].as_str().unwrap_or("");
                Ok(format!(
                    "✅ Created spreadsheet '{}'. ID: {}\nURL: {}",
                    args.range_name, new_id, link
                ))
            }

            other => Err(GoogleToolError(format!(
                "Unknown action '{}'. Use: read, append, update, create.",
                other
            ))),
        }
    }
}

// ── Sheets helper ──

fn parse_values_json(
    raw: Option<&str>,
) -> Result<Vec<Vec<serde_json::Value>>, GoogleToolError> {
    let raw = raw
        .filter(|s| !s.is_empty())
        .ok_or_else(|| GoogleToolError("values_json is required for this action".into()))?;

    serde_json::from_str::<Vec<Vec<serde_json::Value>>>(raw).map_err(|e| {
        GoogleToolError(format!(
            "values_json must be a JSON array-of-arrays (e.g. [[\"a\",1]]). Parse error: {}",
            e
        ))
    })
}