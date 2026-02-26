use crate::llm;
use crate::state::{McpConnection, SharedState};
use axum::extract::ws::{Message, WebSocket};
use futures::stream::SplitSink;
use futures::SinkExt;
use rig::message::{AssistantContent, Message as RigMessage, UserContent};
use rig::OneOrMany;
use rmcp::transport::TokioChildProcess;
use rmcp::ServiceExt;
use serde_json::json;

pub async fn process_message(
    text: &str,
    sender: &mut SplitSink<WebSocket, Message>,
    chat_history: &mut Vec<RigMessage>,
    state: &SharedState,
) {
    let data: serde_json::Value = match serde_json::from_str(text) {
        Ok(v) => v,
        Err(e) => {
            println!("❌ Invalid JSON: {}", e);
            return;
        }
    };

    if let Some(data_type) = data.get("data_type").and_then(|v| v.as_str()) {
        handle_config(data_type, &data, sender, chat_history, state).await;
    } else {
        handle_chat(&data, sender, chat_history, state).await;
    }
}

async fn handle_config(
    data_type: &str,
    data: &serde_json::Value,
    sender: &mut SplitSink<WebSocket, Message>,
    chat_history: &mut Vec<RigMessage>,
    state: &SharedState,
) {
    match data_type {
        "api_key" => {
            let key = data["content"].as_str().unwrap_or("");
            println!("🔑 Received API Key");
            state.lock().await.api_key = Some(key.to_string());
            let _ = sender
                .send(Message::Text(
                    json!({"type": "credentials_success", "content": "API Key stored."}).to_string(),
                ))
                .await;
        }

        "credentials" => {
            let dir_path = data["content"].as_str().unwrap_or("").trim().to_string();
            println!("🔑 Received credentials, dir: {}", dir_path);

            if dir_path.is_empty() {
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "credentials_error", "content": "❌ Credentials directory path is missing."})
                            .to_string(),
                    ))
                    .await;
                return;
            }

            let credentials_path = format!("{}/credentials.json", dir_path);
            let token_path = format!("{}/token.json", dir_path);

            // Validate that credentials.json exists
            if !std::path::Path::new(&credentials_path).exists() {
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "credentials_error", "content": format!("❌ credentials.json not found at: {}", credentials_path)})
                            .to_string(),
                    ))
                    .await;
                return;
            }

            // Attempt authentication: validates token.json, refreshes if expired
            match crate::google_auth::authenticate(&credentials_path, &token_path).await {
                Ok(access_token) => {
                    let mut s = state.lock().await;
                    s.credentials_file_path = Some(credentials_path.clone());
                    s.token_file_path = Some(token_path.clone());
                    s.google_access_token = Some(access_token);
                    drop(s);
                    println!("✅ Google credentials authenticated.");
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "credentials_success", "content": "✅ Credentials received and stored successfully."})
                                .to_string(),
                        ))
                        .await;
                }
                Err(e) => {
                    println!("❌ Authentication error: {}", e);
                    // Delete invalid token file (mirrors Python behaviour)
                    if std::path::Path::new(&token_path).exists() {
                        if let Err(re) = std::fs::remove_file(&token_path) {
                            println!("⚠️ Failed to delete invalid token file: {}", re);
                        } else {
                            println!("🗑️ Deleted invalid token file.");
                        }
                    }
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "credentials_error", "content": format!("❌ Error during authentication: {}", e)})
                                .to_string(),
                        ))
                        .await;
                }
            }
        }

        "revoke_credentials" => {
            println!("🔓 Received Revoke Credentials");
            {
                let mut s = state.lock().await;
                s.api_key = None;
                // Delete token file if present, then clear stored paths
                if let Some(ref token_path) = s.token_file_path {
                    let token_path = token_path.clone();
                    if std::path::Path::new(&token_path).exists() {
                        if let Err(e) = std::fs::remove_file(&token_path) {
                            println!("⚠️ Failed to delete token file: {}", e);
                        } else {
                            println!("🗑️ Deleted token file: {}", token_path);
                        }
                    }
                }
                s.credentials_file_path = None;
                s.token_file_path = None;
                s.google_access_token = None;
            }
            let _ = sender
                .send(Message::Text(
                    json!({"type": "credentials_revoked", "content": "✅ Credentials revoked successfully."})
                        .to_string(),
                ))
                .await;
        }

        "set_llm" => {
            let provider = data["provider"].as_str().unwrap_or("gemini");
            let model = data["model"].as_str().unwrap_or("");
            let api_key = data["api_key"].as_str().unwrap_or("");
            println!("🤖 Set LLM: {} / {}", provider, model);

            if model.is_empty() {
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "llm_set_error", "content": "❌ Model name cannot be empty."})
                            .to_string(),
                    ))
                    .await;
                return;
            }

            if provider != "ollama" && api_key.is_empty() {
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "llm_set_error", "content": "❌ API key is required for this provider."})
                            .to_string(),
                    ))
                    .await;
                return;
            }

            // Verify the credentials/model work before storing
            match llm::verify_llm(provider, api_key, model).await {
                Ok(()) => {
                    let mut s = state.lock().await;
                    s.current_provider = provider.to_string();
                    s.current_model = model.to_string();
                    if !api_key.is_empty() {
                        s.api_key = Some(api_key.to_string());
                    }
                    drop(s);
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "llm_set_success", "content": format!("✅ LLM verified and set to {}/{}", provider, model)})
                                .to_string(),
                        ))
                        .await;
                }
                Err(e) => {
                    println!("❌ Set LLM Error: {}", e);
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "llm_set_error", "content": format!("❌ {}", e)})
                                .to_string(),
                        ))
                        .await;
                }
            }
        }

        "reset_session" => {
            chat_history.clear();
            let _ = sender
                .send(Message::Text(
                    json!({"type": "session_reset", "content": "Session cleared."}).to_string(),
                ))
                .await;
        }

        "mcp_config" => {
            println!("🔧 MCP config received");
            let servers = data
                .get("config")
                .and_then(|c| c.get("mcpServers"))
                .and_then(|s| s.as_object());

            let Some(servers) = servers else {
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "mcp_sync_error", "content": "Invalid MCP config format."})
                            .to_string(),
                    ))
                    .await;
                return;
            };

            // Shut down existing connections
            {
                let mut s = state.lock().await;
                for (name, conn) in s.mcp_connections.drain() {
                    println!("🛑 Stopping MCP server: {}", name);
                    let _ = conn._service.cancel().await;
                }
            }

            let mut statuses: Vec<serde_json::Value> = Vec::new();

            for (name, server_config) in servers {
                let command = match server_config["command"].as_str() {
                    Some(c) => c,
                    None => {
                        statuses.push(
                            json!({"name": name, "status": "error", "error": "Missing command"}),
                        );
                        continue;
                    }
                };

                let args: Vec<String> = server_config["args"]
                    .as_array()
                    .map(|a| {
                        a.iter()
                            .filter_map(|v| v.as_str().map(|s| s.to_string()))
                            .collect()
                    })
                    .unwrap_or_default();

                println!("🔗 Starting MCP server '{}': {} {:?}", name, command, args);

                // Build expanded PATH so we can find npx, node, python, etc.
                let expanded_path = build_expanded_path();

                // Resolve command to full path
                let resolved_command = resolve_command(command, &expanded_path);
                println!("   Resolved command: {}", resolved_command);

                // Build command
                let mut cmd = tokio::process::Command::new(&resolved_command);
                cmd.args(&args);
                cmd.env("PATH", &expanded_path);

                // Set env if provided
                if let Some(env) = server_config["env"].as_object() {
                    for (k, v) in env {
                        if let Some(val) = v.as_str() {
                            cmd.env(k, val);
                        }
                    }
                }

                // Start the MCP server via child process
                let transport = match TokioChildProcess::new(cmd) {
                    Ok(t) => t,
                    Err(e) => {
                        println!("❌ Failed to spawn '{}': {}", name, e);
                        statuses.push(
                            json!({"name": name, "status": "error", "error": e.to_string()}),
                        );
                        continue;
                    }
                };

                let service = match ().serve(transport).await {
                    Ok(s) => s,
                    Err(e) => {
                        println!("❌ Failed to connect to '{}': {:?}", name, e);
                        statuses.push(
                            json!({"name": name, "status": "error", "error": format!("{:?}", e)}),
                        );
                        continue;
                    }
                };

                let tool_list = match service.list_tools(Default::default()).await {
                    Ok(t) => t,
                    Err(e) => {
                        println!("❌ Failed to list tools from '{}': {:?}", name, e);
                        statuses.push(
                            json!({"name": name, "status": "error", "error": format!("{:?}", e)}),
                        );
                        continue;
                    }
                };

                println!(
                    "✅ MCP '{}' connected with {} tools",
                    name,
                    tool_list.tools.len()
                );

                let conn = McpConnection {
                    tools: tool_list.tools,
                    peer: service.peer().clone(),
                    _service: service,
                };

                statuses.push(json!({"name": name, "status": "connected", "error": null}));
                state.lock().await.mcp_connections.insert(name.clone(), conn);
            }

            // Send server statuses
            let _ = sender
                .send(Message::Text(
                    json!({"type": "mcp_server_status", "content": {"servers": statuses}})
                        .to_string(),
                ))
                .await;

            // Send success
            let _ = sender
                .send(Message::Text(
                    json!({"type": "mcp_sync_success", "content": "MCP servers synced."})
                        .to_string(),
                ))
                .await;
        }

        "mcp_status_request" => {
            let s = state.lock().await;
            let servers: Vec<serde_json::Value> = s
                .mcp_connections
                .iter()
                .map(|(name, conn)| {
                    json!({"name": name, "status": "connected", "tools_count": conn.tools.len()})
                })
                .collect();
            drop(s);
            let _ = sender
                .send(Message::Text(
                    json!({"type": "mcp_server_status", "content": {"servers": servers}})
                        .to_string(),
                ))
                .await;
        }

        "tools_request" => {
            let s = state.lock().await;
            let mut tools_list: Vec<serde_json::Value> = vec![
                json!({"name": "calculator", "source": "built-in"}),
                json!({"name": "open_application", "source": "built-in"}),
                json!({"name": "open_chrome_tab", "source": "built-in"}),
                json!({"name": "read_memory", "source": "built-in"}),
                json!({"name": "save_to_memory", "source": "built-in"}),
                json!({"name": "append_to_memory", "source": "built-in"}),
            ];
            if s.google_access_token.is_some() {
                tools_list.push(
                    json!({"name": "google_agent", "source": "google", "description": "Gmail · Calendar · Sheets sub-agent"}),
                );
            }
            for (server_name, conn) in &s.mcp_connections {
                for tool in &conn.tools {
                    tools_list
                        .push(json!({"name": tool.name, "source": format!("mcp:{}", server_name)}));
                }
            }
            drop(s);
            let _ = sender
                .send(Message::Text(
                    json!({"type": "active_tools", "content": {"tools": tools_list}}).to_string(),
                ))
                .await;
        }

        "get_sheet_tabs" => {
            let spreadsheet_id = data["spreadsheet_id"].as_str().unwrap_or("").to_string();
            println!("📊 Get Sheet Tabs for: {}", spreadsheet_id);

            if spreadsheet_id.is_empty() {
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "sheet_tabs_result", "content": {"success": false, "error": "Missing spreadsheet_id."}})
                            .to_string(),
                    ))
                    .await;
                return;
            }

            let access_token = state.lock().await.google_access_token.clone();
            let Some(token) = access_token else {
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "sheet_tabs_result", "content": {"success": false, "error": "Not authenticated with Google. Please connect your Google account first."}})
                            .to_string(),
                    ))
                    .await;
                return;
            };

            // Fetch spreadsheet metadata from the Sheets API
            let url = format!(
                "https://sheets.googleapis.com/v4/spreadsheets/{}?fields=properties.title,sheets.properties.title",
                spreadsheet_id
            );

            let client = reqwest::Client::new();
            match client.get(&url).bearer_auth(&token).send().await {
                Ok(resp) if resp.status().is_success() => {
                    let body: serde_json::Value =
                        resp.json().await.unwrap_or_default();
                    let title = body["properties"]["title"]
                        .as_str()
                        .unwrap_or("")
                        .to_string();
                    let tabs: Vec<String> = body["sheets"]
                        .as_array()
                        .unwrap_or(&vec![])
                        .iter()
                        .filter_map(|s| {
                            s["properties"]["title"]
                                .as_str()
                                .map(|t| t.to_string())
                        })
                        .collect();
                    println!(
                        "✅ Sheet '{}' has {} tab(s): {:?}",
                        title,
                        tabs.len(),
                        tabs
                    );
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "sheet_tabs_result", "content": {
                                "success": true,
                                "title": title,
                                "tabs": tabs
                            }})
                            .to_string(),
                        ))
                        .await;
                }
                Ok(resp) => {
                    let status = resp.status();
                    let body = resp.text().await.unwrap_or_default();
                    println!("❌ Sheets API error {}: {}", status, body);
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "sheet_tabs_result", "content": {
                                "success": false,
                                "error": format!("Google API {} – {}", status, body)
                            }})
                            .to_string(),
                        ))
                        .await;
                }
                Err(e) => {
                    println!("❌ Sheets API request failed: {}", e);
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "sheet_tabs_result", "content": {
                                "success": false,
                                "error": format!("HTTP error: {}", e)
                            }})
                            .to_string(),
                        ))
                        .await;
                }
            }
        }

        "sync_spreadsheets" => {
            let raw_configs = data["configs"].as_array().cloned().unwrap_or_default();
            let mut configs: Vec<crate::state::SpreadsheetConfig> = Vec::new();
            for c in &raw_configs {
                let alias = c["alias"].as_str().unwrap_or("").to_string();
                let sheet_id = c["sheetID"].as_str().unwrap_or("").to_string();
                let selected_tab = c["selectedTab"].as_str().unwrap_or("").to_string();
                let description = c["description"].as_str().unwrap_or("").to_string();
                if !alias.is_empty() && !sheet_id.is_empty() {
                    configs.push(crate::state::SpreadsheetConfig {
                        alias,
                        sheet_id,
                        selected_tab,
                        description,
                    });
                }
            }
            let count = configs.len();
            println!(
                "📊 Synced {} spreadsheet config(s): {:?}",
                count,
                configs.iter().map(|c| &c.alias).collect::<Vec<_>>()
            );
            state.lock().await.spreadsheet_configs = configs;
            let _ = sender
                .send(Message::Text(
                    json!({"type": "spreadsheets_synced", "content": format!("✅ Synced {} spreadsheet(s)", count)})
                        .to_string(),
                ))
                .await;
        }

        "get_memory" => {
            let memory_path = crate::tools::default_memory_path();
            let content = tokio::fs::read_to_string(&memory_path).await.unwrap_or_default();
            let _ = sender
                .send(Message::Text(
                    json!({"type": "memory_content", "content": content}).to_string(),
                ))
                .await;
        }

        "save_memory" => {
            let content = data["content"].as_str().unwrap_or("");
            let memory_path = crate::tools::default_memory_path();
            let result = async {
                if let Some(parent) = memory_path.parent() {
                    tokio::fs::create_dir_all(parent).await?;
                }
                tokio::fs::write(&memory_path, content).await
            }
            .await;
            match result {
                Ok(()) => {
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "memory_saved", "content": "✅ Memory saved successfully"})
                                .to_string(),
                        ))
                        .await;
                }
                Err(e) => {
                    println!("❌ Failed to save memory: {}", e);
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "memory_error", "content": format!("❌ Error saving memory: {}", e)})
                                .to_string(),
                        ))
                        .await;
                }
            }
        }

        "start_oauth" => {
            let dir_path = data["dir_path"].as_str().unwrap_or("").trim().to_string();
            if dir_path.is_empty() {
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "credentials_error", "content": "❌ dir_path is required for start_oauth."})
                            .to_string(),
                    ))
                    .await;
                return;
            }

            let credentials_path = format!("{}/credentials.json", dir_path);
            let token_path = format!("{}/token.json", dir_path);

            if !std::path::Path::new(&credentials_path).exists() {
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "credentials_error", "content": format!("❌ credentials.json not found at: {}", credentials_path)})
                            .to_string(),
                    ))
                    .await;
                return;
            }

            // Bind listener + build consent URL
            match crate::google_auth::prepare_oauth_flow(&credentials_path).await {
                Ok((auth_url, listener)) => {
                    println!("🌐 OAuth URL ready. Sending to client to open in browser.");
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "oauth_url", "content": auth_url}).to_string(),
                        ))
                        .await;

                    // Block this handler while waiting for the browser callback (5 min timeout)
                    match tokio::time::timeout(
                        std::time::Duration::from_secs(300),
                        crate::google_auth::await_oauth_callback(
                            listener,
                            &credentials_path,
                            &token_path,
                        ),
                    )
                    .await
                    {
                        Ok(Ok(access_token)) => {
                            let mut s = state.lock().await;
                            s.credentials_file_path = Some(credentials_path);
                            s.token_file_path = Some(token_path);
                            s.google_access_token = Some(access_token);
                            drop(s);
                            let _ = sender
                                .send(Message::Text(
                                    json!({"type": "credentials_success", "content": "✅ Google authentication successful."})
                                        .to_string(),
                                ))
                                .await;
                        }
                        Ok(Err(e)) => {
                            println!("❌ OAuth callback error: {}", e);
                            let _ = sender
                                .send(Message::Text(
                                    json!({"type": "credentials_error", "content": format!("❌ OAuth failed: {}", e)})
                                        .to_string(),
                                ))
                                .await;
                        }
                        Err(_) => {
                            let _ = sender
                                .send(Message::Text(
                                    json!({"type": "credentials_error", "content": "❌ OAuth timed out (5 min). Please try again."})
                                        .to_string(),
                                ))
                                .await;
                        }
                    }
                }
                Err(e) => {
                    println!("❌ Failed to prepare OAuth flow: {}", e);
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "credentials_error", "content": format!("❌ Failed to start OAuth: {}", e)})
                                .to_string(),
                        ))
                        .await;
                }
            }
        }

        _ => {
            println!("⚠️ Unknown data_type: {}", data_type);
        }
    }
}

async fn handle_chat(
    data: &serde_json::Value,
    sender: &mut SplitSink<WebSocket, Message>,
    chat_history: &mut Vec<RigMessage>,
    state: &SharedState,
) {
    let query = data["text"].as_str().unwrap_or("").trim().to_string();

    if query.is_empty() {
        let _ = sender
            .send(Message::Text(
                json!({"type": "response", "content": {"text": "Please enter a message.", "images": [], "widgets": []}})
                    .to_string(),
            ))
            .await;
        return;
    }

    let (api_key, model, provider, mcp_tool_sets, google_access_token, spreadsheet_configs) = {
        let s = state.lock().await;
        (
            s.api_key.clone(),
            s.current_model.clone(),
            s.current_provider.clone(),
            s.all_mcp_tools(),
            s.google_access_token.clone(),
            s.spreadsheet_configs.clone(),
        )
    };

    let user_name = data["user_name"].as_str().map(|s| s.to_string());

    // Ollama doesn't need an API key; others do
    if provider != "ollama"
        && api_key.as_ref().is_none_or(|k| k.is_empty())
    {
        let _ = sender
            .send(Message::Text(
                json!({"type": "response", "content": {"text": "No API key configured. Please set your API key in Settings.", "images": [], "widgets": []}})
                    .to_string(),
            ))
            .await;
        return;
    }
    
    // Channel for tool-call events emitted during LLM execution
    let (tool_tx, mut tool_rx) = tokio::sync::mpsc::channel::<serde_json::Value>(64);

    // Spawn LLM in a separate task so we can forward tool events concurrently
    let system_prompt = data["system_prompt"].as_str().map(|s| s.to_string());
    let base64_image = data["base64_image"].as_str().map(|s| s.to_string());
    let history_clone = chat_history.clone();

    let mut llm_task = tokio::spawn(llm::call_llm(
        provider,
        api_key.unwrap_or_default(),
        model,
        query.clone(),
        history_clone,
        mcp_tool_sets,
        system_prompt,
        base64_image,
        google_access_token,
        spreadsheet_configs,
        tool_tx,
        user_name,
    ));

    // Forward tool_call / tool_result events while the LLM task is running.
    // biased: drain all pending events before checking task completion.
    let llm_result = loop {
        tokio::select! {
            biased;
            Some(event) = tool_rx.recv() => {
                let _ = sender.send(Message::Text(event.to_string())).await;
            }
            outcome = &mut llm_task => {
                // Drain any events that arrived just before the task finished
                while let Ok(event) = tool_rx.try_recv() {
                    let _ = sender.send(Message::Text(event.to_string())).await;
                }
                break outcome;
            }
        }
    };

    let result = match llm_result {
        Ok(r) => r,
        Err(join_err) => Err(format!("LLM task panicked: {}", join_err)),
    };

    match result {
        Ok(text) => {
            chat_history.push(RigMessage::User {
                content: OneOrMany::one(UserContent::text(query.clone())),
            });
            chat_history.push(RigMessage::Assistant {
                id: Default::default(),
                content: OneOrMany::one(AssistantContent::text(text.clone())),
            });
            let _ = sender
                .send(Message::Text(
                    json!({"type": "response", "content": {"text": text, "images": [], "widgets": []}})
                        .to_string(),
                ))
                .await;
        }
        Err(e) => {
            println!("❌ LLM error: {}", e);
            let _ = sender
                .send(Message::Text(
                    json!({"type": "response", "content": {"text": format!("Error: {}", e), "images": [], "widgets": []}})
                        .to_string(),
                ))
                .await;
        }
    }
}

/// Build an expanded PATH that includes common tool locations
fn build_expanded_path() -> String {
    let home = dirs::home_dir().unwrap_or_default();
    let home_str = home.to_string_lossy();

    let mut extra_paths: Vec<String> = Vec::new();

    // nvm node versions
    let nvm_dir = home.join(".nvm").join("versions").join("node");
    if let Ok(entries) = std::fs::read_dir(&nvm_dir) {
        for entry in entries.flatten() {
            let bin = entry.path().join("bin");
            if bin.is_dir() {
                extra_paths.push(bin.to_string_lossy().to_string());
            }
        }
    }

    // Common tool directories
    let common_dirs = [
        format!("{}/.local/bin", home_str),           // pipx, uv
        "/opt/homebrew/bin".to_string(),               // Homebrew (Apple Silicon)
        "/usr/local/bin".to_string(),                  // Homebrew (Intel)
        "/opt/local/bin".to_string(),                  // MacPorts
        format!("{}/.cargo/bin", home_str),            // Rust/cargo
        format!("{}/go/bin", home_str),                // Go
    ];

    for dir in &common_dirs {
        if std::path::Path::new(dir).is_dir() {
            extra_paths.push(dir.clone());
        }
    }

    // Append the existing PATH
    let existing = std::env::var("PATH").unwrap_or_default();
    if !existing.is_empty() {
        extra_paths.push(existing);
    }

    extra_paths.join(":")
}

/// Resolve a command name to its full path using the expanded PATH
fn resolve_command(command: &str, path: &str) -> String {
    // If already an absolute path, return as-is
    if command.starts_with('/') {
        return command.to_string();
    }

    for dir in path.split(':') {
        let candidate = std::path::Path::new(dir).join(command);
        if candidate.is_file() {
            return candidate.to_string_lossy().to_string();
        }
    }

    // Fallback to the command name itself
    command.to_string()
}
