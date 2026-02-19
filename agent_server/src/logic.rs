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
            println!("🔑 Received credentials");
            let _ = sender
                .send(Message::Text(
                    json!({"type": "credentials_success", "content": "Credentials received."})
                        .to_string(),
                ))
                .await;
        }

        "revoke_credentials" => {
            println!("🔓 Received Revoke Credentials");
            state.lock().await.api_key = None;
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
                json!({"name": "get_current_date_time", "source": "built-in"}),
                json!({"name": "open_application", "source": "built-in"}),
                json!({"name": "open_chrome_tab", "source": "built-in"}),
                json!({"name": "read_memory", "source": "built-in"}),
                json!({"name": "save_to_memory", "source": "built-in"}),
                json!({"name": "append_to_memory", "source": "built-in"}),
            ];
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
            let spreadsheet_id = data["spreadsheet_id"].as_str().unwrap_or("");
            println!("📊 Received Sheet Tabs Request for: {}", spreadsheet_id);
            // Google Sheets integration is not implemented in the Rust server
            let _ = sender
                .send(Message::Text(
                    json!({"type": "sheet_tabs_result", "content": {"success": false, "error": "Google Sheets integration is not supported by this server."}})
                        .to_string(),
                ))
                .await;
        }

        "sync_spreadsheets" => {
            let configs = data["configs"].as_array();
            let count = configs.map(|c| c.len()).unwrap_or(0);
            println!("📊 Received Spreadsheet Configs: {} sheet(s)", count);
            let _ = sender
                .send(Message::Text(
                    json!({"type": "spreadsheets_synced", "content": format!("✅ Synced {} spreadsheet(s)", count)})
                        .to_string(),
                ))
                .await;
        }

        "get_memory" => {
            let memory_path = crate::tools::default_memory_path();
            let content = match tokio::fs::read_to_string(&memory_path).await {
                Ok(c) => c,
                Err(_) => String::new(),
            };
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

    let (api_key, model, provider, mcp_tool_sets) = {
        let s = state.lock().await;
        (
            s.api_key.clone(),
            s.current_model.clone(),
            s.current_provider.clone(),
            s.all_mcp_tools(),
        )
    };

    // Ollama doesn't need an API key; others do
    if provider != "ollama" {
        if api_key.as_ref().map_or(true, |k| k.is_empty()) {
            let _ = sender
                .send(Message::Text(
                    json!({"type": "response", "content": {"text": "No API key configured. Please set your API key in Settings.", "images": [], "widgets": []}})
                        .to_string(),
                ))
                .await;
            return;
        }
    }

    let _ = sender
        .send(Message::Text(
            json!({"type": "thought", "content": {"text": "Thinking..."}}).to_string(),
        ))
        .await;

    let result = llm::call_llm(
        &provider,
        api_key.as_deref().unwrap_or(""),
        &model,
        &query,
        chat_history.clone(),
        mcp_tool_sets,
        data["system_prompt"].as_str(),
        data["base64_image"].as_str(),
    )
    .await;

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
