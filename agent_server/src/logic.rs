use crate::llm;
use crate::state::{McpConnection, SharedState};
use axum::extract::ws::{Message, WebSocket};
use futures::stream::SplitSink;
use futures::SinkExt;
use rig::message::{AssistantContent, Message as RigMessage, UserContent};
use rig::OneOrMany;
use rmcp::transport::streamable_http_client::{
    StreamableHttpClientTransport, StreamableHttpClientTransportConfig,
};
use rmcp::transport::TokioChildProcess;
use rmcp::ServiceExt;
use serde_json::json;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

struct BuiltinServerDef {
    name: &'static str,
    command: &'static str,
    args_template: &'static [&'static str],
}

const BUILTIN_SERVERS: &[BuiltinServerDef] = &[
    BuiltinServerDef {
        name: "filesystem",
        command: "npx",
        args_template: &["-y", "@modelcontextprotocol/server-filesystem"],
    },
    BuiltinServerDef {
        name: "fetch",
        command: "npx",
        args_template: &["-y", "@modelcontextprotocol/server-fetch"],
    },
    BuiltinServerDef {
        name: "shell",
        command: "npx",
        args_template: &["-y", "@modelcontextprotocol/server-shell"],
    },
    BuiltinServerDef {
        name: "memory",
        command: "npx",
        args_template: &["-y", "@modelcontextprotocol/server-memory"],
    },
];

/// Extract a human-readable message from a rig/API error string.
fn clean_llm_error(raw: &str) -> String {
    let mut search_start = 0;
    while let Some(offset) = raw[search_start..].find('{') {
        let start = search_start + offset;
        let mut depth = 0usize;
        let mut end = None;
        for (i, ch) in raw[start..].char_indices() {
            match ch {
                '{' => depth += 1,
                '}' => {
                    depth = depth.saturating_sub(1);
                    if depth == 0 {
                        end = Some(start + i + 1);
                        break;
                    }
                }
                _ => {}
            }
        }
        if let Some(end) = end
            && let Ok(v) = serde_json::from_str::<serde_json::Value>(&raw[start..end])
        {
            if let Some(msg) = v.pointer("/error/message").and_then(|m| m.as_str()) {
                return msg.to_string();
            }
            if let Some(msg) = v.get("message").and_then(|m| m.as_str()) {
                return msg.to_string();
            }
        }
        search_start = start + 1;
    }
    if let Some(after) = raw.find("with message:") {
        let msg = raw[after + "with message:".len()..].trim();
        if !msg.is_empty() {
            return msg.to_string();
        }
    }
    raw.to_string()
}

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
        // ── API key (manual entry) ──────────────────────────────────────────
        "api_key" => {
            let key = data["content"].as_str().unwrap_or("");
            println!("🔑 Received API Key");
            let provider = state.lock().await.current_provider.clone();
            state.lock().await.api_keys.insert(provider, key.to_string());
            let _ = sender
                .send(Message::Text(
                    json!({"type": "credentials_success", "content": "API key saved — you're all set!"}).to_string(),
                ))
                .await;
        }

        // ── Set LLM provider / model ────────────────────────────────────────
        "set_llm" => {
            let provider = data["provider"].as_str().unwrap_or("gemini");
            let model = data["model"].as_str().unwrap_or("");
            let api_key = data["api_key"].as_str().unwrap_or("");
            println!("🤖 Set LLM: {} / {}", provider, model);

            if model.is_empty() {
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "llm_set_error", "content": "Please specify which model you'd like to use."})
                            .to_string(),
                    ))
                    .await;
                return;
            }

            // For OpenRouter, use the OAuth-stored key when none is provided.
            // For Ollama, no key is needed at all.
            let effective_key = if api_key.is_empty() && provider == "openrouter" {
                state
                    .lock()
                    .await
                    .api_keys
                    .get("openrouter")
                    .cloned()
                    .unwrap_or_default()
            } else {
                api_key.to_string()
            };

            // Require a key for providers that aren't Ollama/OpenRouter (Ollama has
            // no key at all; OpenRouter uses OAuth and we check the stored key below).
            let key_exempt = provider == "ollama";
            if !key_exempt && provider != "openrouter" && effective_key.is_empty() {
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "llm_set_error", "content": format!("An API key is required for {}. Please add it in Settings.", provider)})
                            .to_string(),
                    ))
                    .await;
                return;
            }

            // For OpenRouter, ensure the user has completed OAuth before trying to
            // set it as the active provider.
            if provider == "openrouter" && effective_key.is_empty() {
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "llm_set_error", "content": "Please sign in to OpenRouter first (Settings → OpenRouter → Connect)."})
                            .to_string(),
                    ))
                    .await;
                return;
            }

            match llm::verify_llm(provider, &effective_key, model).await {
                Ok(()) => {
                    let mut s = state.lock().await;
                    s.current_provider = provider.to_string();
                    s.current_model = model.to_string();
                    if !effective_key.is_empty() {
                        s.api_keys.insert(provider.to_string(), effective_key);
                    }
                    drop(s);
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "llm_set_success", "content": format!("Now using {} via {}. Ready to chat!", model, provider)})
                                .to_string(),
                        ))
                        .await;
                }
                Err(e) => {
                    println!("❌ Set LLM Error: {}", e);
                    let readable = clean_llm_error(&e);
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "llm_set_error", "content": format!("Could not connect to {} — {}. Please verify your API key and model name.", model, readable)})
                                .to_string(),
                        ))
                        .await;
                }
            }
        }

        // ── OpenRouter PKCE OAuth ───────────────────────────────────────────
        "start_openrouter_oauth" => {
            match crate::openrouter_auth::prepare_openrouter_flow().await {
                Ok((auth_url, verifier, state_nonce, listener)) => {
                    println!("🌐 OpenRouter OAuth URL ready. Sending to client.");
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "openrouter_oauth_url", "content": auth_url})
                                .to_string(),
                        ))
                        .await;

                    match tokio::time::timeout(
                        std::time::Duration::from_secs(300),
                        crate::openrouter_auth::await_openrouter_callback(
                            listener,
                            &verifier,
                            &state_nonce,
                        ),
                    )
                    .await
                    {
                        Ok(Ok(api_key)) => {
                            let api_key: String = api_key;
                            state
                                .lock()
                                .await
                                .api_keys
                                .insert("openrouter".to_string(), api_key.clone());
                            let _ = sender
                                .send(Message::Text(
                                    json!({"type": "openrouter_oauth_success", "content": api_key})
                                        .to_string(),
                                ))
                                .await;
                        }
                        Ok(Err(e)) => {
                            println!("❌ OpenRouter OAuth callback error: {}", e);
                            let _ = sender
                                .send(Message::Text(
                                    json!({"type": "openrouter_oauth_error", "content": e})
                                        .to_string(),
                                ))
                                .await;
                        }
                        Err(_) => {
                            let _ = sender
                                .send(Message::Text(
                                    json!({"type": "openrouter_oauth_error", "content": "Sign-in timed out. Please try again."})
                                        .to_string(),
                                ))
                                .await;
                        }
                    }
                }
                Err(e) => {
                    println!("❌ Failed to prepare OpenRouter OAuth flow: {}", e);
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "openrouter_oauth_error", "content": format!("Could not start the sign-in process: {}.", e)})
                                .to_string(),
                        ))
                        .await;
                }
            }
        }

        // ── Google OAuth via backend/ proxy ────────────────────────────────
        "set_backend_url" => {
            let url = data["url"].as_str().unwrap_or("").trim().to_string();
            if !url.is_empty() {
                println!("🌐 Backend URL set to: {}", url);
                state.lock().await.backend_url = url;
            }
        }

        "start_oauth" => {
            let backend_url = state.lock().await.backend_url.clone();
            println!("🔐 Starting Google OAuth via backend: {}", backend_url);

            // Bind a loopback listener so the backend can redirect back to us.
            let listener = match tokio::net::TcpListener::bind("127.0.0.1:0").await {
                Ok(l) => l,
                Err(e) => {
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "credentials_error", "content": format!("Could not start the local auth server: {}", e)})
                                .to_string(),
                        ))
                        .await;
                    return;
                }
            };
            let port = listener.local_addr().unwrap().port();
            let redirect_uri = format!("http://localhost:{}", port);

            // Ask the backend for the Google consent URL (don't follow the redirect).
            let no_redirect_client = match reqwest::Client::builder()
                .redirect(reqwest::redirect::Policy::none())
                .build()
            {
                Ok(c) => c,
                Err(e) => {
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "credentials_error", "content": format!("HTTP client error: {}", e)})
                                .to_string(),
                        ))
                        .await;
                    return;
                }
            };

            let login_url = format!(
                "{}/auth/google/login?redirectUri={}",
                backend_url,
                urlencoding::encode(&redirect_uri)
            );

            let resp = match no_redirect_client.get(&login_url).send().await {
                Ok(r) => r,
                Err(e) => {
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "credentials_error", "content": format!("Could not reach the authentication server. Is the backend running? ({})", e)})
                                .to_string(),
                        ))
                        .await;
                    return;
                }
            };

            let oauth_url = match resp
                .headers()
                .get("location")
                .and_then(|v| v.to_str().ok())
                .map(|s| s.to_string())
            {
                Some(u) => u,
                None => {
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "credentials_error", "content": "The authentication server did not return an OAuth URL. Check the backend is configured correctly."})
                                .to_string(),
                        ))
                        .await;
                    return;
                }
            };

            // Send the consent URL so Swift can open it in the browser.
            let _ = sender
                .send(Message::Text(
                    json!({"type": "oauth_url", "content": oauth_url}).to_string(),
                ))
                .await;

            // Wait for Google to redirect back to our loopback listener (5 min).
            match tokio::time::timeout(
                std::time::Duration::from_secs(300),
                await_google_callback(listener),
            )
            .await
            {
                Ok(Ok(login_token)) => {
                    // Exchange the one-time login token for a long-lived JWT.
                    let consume_url = format!("{}/auth/google/consume", backend_url);
                    let consume_result = no_redirect_client
                        .post(&consume_url)
                        .json(&serde_json::json!({"token": login_token}))
                        .send()
                        .await;

                    match consume_result {
                        Ok(r) if r.status().is_success() => {
                            let body: serde_json::Value =
                                r.json().await.unwrap_or_default();
                            let jwt = body["token"].as_str().unwrap_or("").to_string();
                            if jwt.is_empty() {
                                let _ = sender
                                    .send(Message::Text(
                                        json!({"type": "credentials_error", "content": "The authentication server did not return a session token."})
                                            .to_string(),
                                    ))
                                    .await;
                                return;
                            }
                            state.lock().await.google_session_token = Some(jwt.clone());
                            // Send the JWT to Swift so it can persist it across restarts.
                            let _ = sender
                                .send(Message::Text(
                                    json!({"type": "session_token", "content": jwt}).to_string(),
                                ))
                                .await;
                            let _ = sender
                                .send(Message::Text(
                                    json!({"type": "credentials_success", "content": "Google account connected! You now have access to Gmail and Calendar."})
                                        .to_string(),
                                ))
                                .await;
                        }
                        Ok(r) => {
                            let status = r.status().as_u16();
                            let _ = sender
                                .send(Message::Text(
                                    json!({"type": "credentials_error", "content": format!("Session exchange failed (status {}). Please try signing in again.", status)})
                                        .to_string(),
                                ))
                                .await;
                        }
                        Err(e) => {
                            let _ = sender
                                .send(Message::Text(
                                    json!({"type": "credentials_error", "content": format!("Could not reach the authentication server to complete sign-in: {}", e)})
                                        .to_string(),
                                ))
                                .await;
                        }
                    }
                }
                Ok(Err(e)) => {
                    println!("❌ Google OAuth callback error: {}", e);
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "credentials_error", "content": format!("Sign-in was not completed: {}", e)})
                                .to_string(),
                        ))
                        .await;
                }
                Err(_) => {
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "credentials_error", "content": "Sign-in timed out — the browser authorization wasn't completed within 5 minutes. Please try again."})
                                .to_string(),
                        ))
                        .await;
                }
            }
        }

        "restore_session" => {
            let token = data["session_token"].as_str().unwrap_or("").trim().to_string();
            if token.is_empty() {
                state.lock().await.google_session_token = None;
                return;
            }
            println!("🔄 Restoring Google session from stored JWT.");
            state.lock().await.google_session_token = Some(token);
            let _ = sender
                .send(Message::Text(
                    json!({"type": "credentials_success", "content": "Google account restored."}).to_string(),
                ))
                .await;
        }

        "revoke_credentials" => {
            state.lock().await.google_session_token = None;
            let _ = sender
                .send(Message::Text(
                    json!({"type": "credentials_revoked", "content": "Google account disconnected."}).to_string(),
                ))
                .await;
        }

        // ── Session / memory ────────────────────────────────────────────────
        "reset_session" => {
            chat_history.clear();
            let _ = sender
                .send(Message::Text(
                    json!({"type": "session_reset", "content": "Conversation cleared — starting fresh!"}).to_string(),
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
                            json!({"type": "memory_saved", "content": "Memory updated successfully."})
                                .to_string(),
                        ))
                        .await;
                }
                Err(e) => {
                    println!("❌ Failed to save memory: {}", e);
                    let _ = sender
                        .send(Message::Text(
                            json!({"type": "memory_error", "content": "Could not save memory notes. Please try again."})
                                .to_string(),
                        ))
                        .await;
                }
            }
        }

        // ── MCP (user-managed servers) ──────────────────────────────────────
        "mcp_config" => {
            println!("🔧 MCP config received");
            let servers = data
                .get("config")
                .and_then(|c| c.get("mcpServers"))
                .and_then(|s| s.as_object());

            let Some(servers) = servers else {
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "mcp_sync_error", "content": "The MCP configuration couldn't be read. Please check your settings."})
                            .to_string(),
                    ))
                    .await;
                return;
            };

            // Shut down all existing MCP connections before starting the new set.
            {
                let mut s = state.lock().await;
                let to_remove: Vec<String> = s.mcp_connections.keys().cloned().collect();
                for name in to_remove {
                    if let Some(conn) = s.mcp_connections.remove(&name) {
                        println!("🛑 Stopping MCP server: {}", name);
                        let _ = conn._service.cancel().await;
                    }
                }
            }

            let mut statuses: Vec<serde_json::Value> = Vec::new();

            for (name, server_config) in servers {
                // Prefix reserved built-in server names to avoid collisions
                let reserved = ["filesystem", "fetch", "shell", "memory"];
                let name = if reserved.contains(&name.as_str()) {
                    format!("custom:{}", name)
                } else {
                    name.clone()
                };

                let transport_type = server_config["transport"].as_str().unwrap_or("stdio");

                if transport_type == "http" {
                    // --- HTTP/SSE transport path ---
                    let url = match server_config["url"].as_str() {
                        Some(u) => u.to_string(),
                        None => {
                            statuses.push(
                                json!({"name": name, "status": "error", "error": "Missing url for HTTP transport"}),
                            );
                            continue;
                        }
                    };
                    let api_key = server_config["api_key"].as_str().unwrap_or("");

                    println!("🔗 Connecting to HTTP MCP server '{}': {}", name, url);

                    match connect_http_mcp_server(&url, api_key).await {
                        Ok(conn) => {
                            println!(
                                "✅ MCP '{}' connected with {} tools",
                                name,
                                conn.tools.len()
                            );
                            statuses.push(json!({"name": name, "status": "connected", "error": null}));
                            state.lock().await.mcp_connections.insert(name.clone(), conn);
                        }
                        Err(e) => {
                            println!("❌ Failed to connect HTTP MCP '{}': {}", name, e);
                            statuses.push(
                                json!({"name": name, "status": "error", "error": e}),
                            );
                        }
                    }
                } else {
                    // --- stdio (child process) transport path ---
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
            }

            let _ = sender
                .send(Message::Text(
                    json!({"type": "mcp_server_status", "content": {"servers": statuses}})
                        .to_string(),
                ))
                .await;
            let _ = sender
                .send(Message::Text(
                    json!({"type": "mcp_sync_success", "content": "MCP servers are connected and ready!"})
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
                json!({"name": "calculator", "source": "built-in", "description": "Evaluate mathematical expressions"}),
                json!({"name": "open_application", "source": "built-in", "description": "Launch a macOS application by name"}),
                json!({"name": "open_chrome_tab", "source": "built-in", "description": "Open a URL in Google Chrome"}),
                json!({"name": "read_memory", "source": "built-in", "description": "Read from the agent's persistent knowledge base"}),
                json!({"name": "save_to_memory", "source": "built-in", "description": "Save information to the agent's persistent knowledge base"}),
                json!({"name": "append_to_memory", "source": "built-in", "description": "Append content to an existing memory entry"}),
            ];
            for (server_name, conn) in &s.mcp_connections {
                for tool in &conn.tools {
                    let safe_name = crate::mcp_proxy::sanitize_tool_name(&tool.name);
                    let desc = tool
                        .description
                        .as_deref()
                        .filter(|d| !d.is_empty())
                        .unwrap_or("MCP tool");
                    let source = format!("mcp:{}", server_name);
                    tools_list.push(json!({"name": safe_name, "source": source, "description": desc}));
                }
            }
            drop(s);
            let _ = sender
                .send(Message::Text(
                    json!({"type": "active_tools", "content": {"tools": tools_list}}).to_string(),
                ))
                .await;
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
                    json!({"type": "spreadsheets_synced", "content": format!("{} spreadsheet{} synced and ready to use.", count, if count == 1 { "" } else { "s" })})
                        .to_string(),
                ))
                .await;
        }

        "set_builtin_servers" => {
            println!("🔧 set_builtin_servers received");

            // Parse enabled server names
            let enabled: Vec<String> = data["enabled"]
                .as_array()
                .map(|a| {
                    a.iter()
                        .filter_map(|v| v.as_str().map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();

            // Parse filesystem paths, defaulting to $HOME
            let filesystem_paths: Vec<String> = {
                let from_data: Vec<String> = data["filesystem_paths"]
                    .as_array()
                    .map(|a| {
                        a.iter()
                            .filter_map(|v| v.as_str().map(|s| s.to_string()))
                            .collect()
                    })
                    .unwrap_or_default();
                if from_data.is_empty() {
                    vec![std::env::var("HOME").unwrap_or_else(|_| "/".to_string())]
                } else {
                    from_data
                }
            };

            // Stop any currently running built-in servers NOT in the new enabled list
            {
                let mut s = state.lock().await;
                let to_stop: Vec<String> = s
                    .builtin_servers
                    .keys()
                    .filter(|name| !enabled.contains(name))
                    .cloned()
                    .collect();
                for name in to_stop {
                    if let Some(conn) = s.builtin_servers.remove(&name) {
                        println!("🛑 Stopping built-in server: {}", name);
                        let _ = conn._service.cancel().await;
                    }
                }
            }

            let expanded_path = build_expanded_path();
            let mut statuses: Vec<serde_json::Value> = Vec::new();

            for name in &enabled {
                // For filesystem: always restart so path changes take effect.
                // For other built-ins: skip if already running.
                if state.lock().await.builtin_servers.contains_key(name.as_str()) {
                    if name != "filesystem" {
                        statuses.push(json!({"name": name, "status": "connected", "error": null}));
                        continue;
                    }
                    // Stop the existing filesystem server so it can be restarted with updated paths.
                    if let Some(conn) = state.lock().await.builtin_servers.remove(name.as_str()) {
                        let _ = conn._service.cancel().await;
                    }
                }

                // Look up the server definition
                let def = match BUILTIN_SERVERS.iter().find(|d| d.name == name.as_str()) {
                    Some(d) => d,
                    None => {
                        println!("❌ Unknown built-in server: {}", name);
                        statuses.push(
                            json!({"name": name, "status": "error", "error": format!("Unknown built-in server: {}", name)}),
                        );
                        continue;
                    }
                };

                // Check that npx (Node.js) is available
                let resolved = resolve_command(def.command, &expanded_path);
                if resolved == def.command {
                    println!("❌ {} not found on PATH for server '{}'", def.command, name);
                    statuses.push(
                        json!({"name": name, "status": "error", "error": "Node.js not installed"}),
                    );
                    continue;
                }

                // Build args: template args + filesystem_paths for "filesystem" server
                let mut args: Vec<String> =
                    def.args_template.iter().map(|s| s.to_string()).collect();
                if name == "filesystem" {
                    args.extend(filesystem_paths.iter().cloned());
                }

                println!("🔗 Starting built-in MCP server '{}': {} {:?}", name, resolved, args);

                let mut cmd = tokio::process::Command::new(&resolved);
                cmd.args(&args);
                cmd.env("PATH", &expanded_path);

                let transport = match TokioChildProcess::new(cmd) {
                    Ok(t) => t,
                    Err(e) => {
                        println!("❌ Failed to spawn built-in server '{}': {}", name, e);
                        statuses.push(
                            json!({"name": name, "status": "error", "error": e.to_string()}),
                        );
                        continue;
                    }
                };

                let service = match ().serve(transport).await {
                    Ok(s) => s,
                    Err(e) => {
                        println!("❌ Failed to connect to built-in server '{}': {:?}", name, e);
                        statuses.push(
                            json!({"name": name, "status": "error", "error": format!("{:?}", e)}),
                        );
                        continue;
                    }
                };

                let tool_list = match service.list_tools(Default::default()).await {
                    Ok(t) => t,
                    Err(e) => {
                        println!("❌ Failed to list tools from built-in server '{}': {:?}", name, e);
                        statuses.push(
                            json!({"name": name, "status": "error", "error": format!("{:?}", e)}),
                        );
                        continue;
                    }
                };

                println!(
                    "✅ Built-in MCP '{}' connected with {} tools",
                    name,
                    tool_list.tools.len()
                );

                let conn = McpConnection {
                    tools: tool_list.tools,
                    peer: service.peer().clone(),
                    _service: service,
                };

                statuses.push(json!({"name": name, "status": "connected", "error": null}));
                state.lock().await.builtin_servers.insert(name.clone(), conn);
            }

            // Send server statuses for all requested servers
            let _ = sender
                .send(Message::Text(
                    json!({"type": "mcp_server_status", "content": {"servers": statuses}})
                        .to_string(),
                ))
                .await;
        }

        "set_composio" => {
            let api_key = data["api_key"].as_str().unwrap_or("").trim().to_string();

            if api_key.is_empty() {
                // Disconnect: clear stored key and drop connection
                let mut s = state.lock().await;
                s.composio_api_key = None;
                if let Some(conn) = s.mcp_connections.remove("composio") {
                    let _ = conn._service.cancel().await;
                    println!("🛑 Composio MCP server disconnected");
                }
                drop(s);
                let _ = sender
                    .send(Message::Text(
                        json!({"type": "mcp_server_status", "content": {"servers": [{"name": "composio", "status": "disconnected", "error": null}]}})
                            .to_string(),
                    ))
                    .await;
            } else {
                // Connect: store key and establish HTTP/SSE connection
                println!("🔗 Connecting to Composio MCP server");
                state.lock().await.composio_api_key = Some(api_key.clone());

                match connect_http_mcp_server("https://mcp.composio.dev", &api_key).await {
                    Ok(conn) => {
                        println!(
                            "✅ Composio MCP connected with {} tools",
                            conn.tools.len()
                        );
                        state
                            .lock()
                            .await
                            .mcp_connections
                            .insert("composio".to_string(), conn);
                        let _ = sender
                            .send(Message::Text(
                                json!({"type": "mcp_server_status", "content": {"servers": [{"name": "composio", "status": "connected", "error": null}]}})
                                    .to_string(),
                            ))
                            .await;
                    }
                    Err(e) => {
                        println!("❌ Failed to connect to Composio MCP: {}", e);
                        state.lock().await.composio_api_key = None;
                        let _ = sender
                            .send(Message::Text(
                                json!({"type": "mcp_server_status", "content": {"servers": [{"name": "composio", "status": "error", "error": e}]}})
                                    .to_string(),
                            ))
                            .await;
                    }
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
                json!({"type": "response", "content": {"text": "Looks like your message was empty — type something and I'll help!", "images": [], "widgets": []}})
                    .to_string(),
            ))
            .await;
        return;
    }

    let (api_key, model, provider, mcp_tool_sets) = {
        let s = state.lock().await;
        let key = s.api_keys.get(&s.current_provider).cloned();
        (
            key,
            s.current_model.clone(),
            s.current_provider.clone(),
            s.all_mcp_tools(),
        )
    };

    let user_name = data["user_name"].as_str().map(|s| s.to_string());

    if provider != "ollama"
        && provider != "openrouter"
        && api_key.as_ref().is_none_or(|k| k.is_empty())
    {
        let _ = sender
            .send(Message::Text(
                json!({"type": "response", "content": {"text": "No API key set up yet. Please add your API key in Settings to get started.", "images": [], "widgets": []}})
                    .to_string(),
            ))
            .await;
        return;
    }

    let (tool_tx, mut tool_rx) = tokio::sync::mpsc::channel::<serde_json::Value>(64);

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
        tool_tx,
        user_name,
    ));

    let llm_result = loop {
        tokio::select! {
            biased;
            Some(event) = tool_rx.recv() => {
                let _ = sender.send(Message::Text(event.to_string())).await;
            }
            outcome = &mut llm_task => {
                while let Ok(event) = tool_rx.try_recv() {
                    let _ = sender.send(Message::Text(event.to_string())).await;
                }
                break outcome;
            }
        }
    };

    let result = match llm_result {
        Ok(r) => r,
        Err(join_err) => {
            println!("❌ LLM task panicked: {}", join_err);
            let _ = sender
                .send(Message::Text(
                    json!({"type": "response", "content": {"text": "Something went wrong on my end. Please try your request again.", "images": [], "widgets": []}})
                        .to_string(),
                ))
                .await;
            return;
        }
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
                    json!({"type": "response", "content": {"text": format!("I ran into an issue: {}\n\nPlease try again.", e), "images": [], "widgets": []}})
                        .to_string(),
                ))
                .await;
        }
    }
}

/// Connect to an HTTP/SSE MCP server using the streamable-http transport.
///
/// The `Authorization: Bearer <api_key>` header is sent with every request when
/// `api_key` is non-empty.  The returned `McpConnection` contains the raw tool
/// list and a peer handle; the caller is responsible for inserting it into
/// `state.mcp_connections`.
async fn connect_http_mcp_server(
    url: &str,
    api_key: &str,
) -> Result<McpConnection, String> {
    let config = {
        let base = StreamableHttpClientTransportConfig::with_uri(url);
        if api_key.is_empty() {
            base
        } else {
            base.auth_header(format!("Bearer {}", api_key))
        }
    };

    let transport = StreamableHttpClientTransport::from_config(config);

    let service = tokio::time::timeout(
        std::time::Duration::from_secs(30),
        ().serve(transport),
    )
    .await
    .map_err(|_| "Connection timed out after 30s".to_string())?
    .map_err(|e| format!("MCP handshake failed: {:?}", e))?;

    let tool_list = tokio::time::timeout(
        std::time::Duration::from_secs(15),
        service.list_tools(Default::default()),
    )
    .await
    .map_err(|_| "list_tools timed out after 15s".to_string())?
    .map_err(|e| format!("list_tools failed: {:?}", e))?;

    let conn = McpConnection {
        tools: tool_list.tools,
        peer: service.peer().clone(),
        _service: service,
    };

    Ok(conn)
}

/// Wait for the browser to be redirected back to our loopback listener after
/// Google OAuth.  The backend appends `?token={one_time_token}` to the URI.
async fn await_google_callback(
    listener: tokio::net::TcpListener,
) -> Result<String, String> {
    let (mut stream, peer_addr) = listener
        .accept()
        .await
        .map_err(|e| format!("Did not receive a response from the browser: {}", e))?;

    if !peer_addr.ip().is_loopback() {
        return Err("Rejected non-loopback OAuth callback.".to_string());
    }

    let mut buf = vec![0u8; 8192];
    let n = stream
        .read(&mut buf)
        .await
        .map_err(|e| format!("Could not read browser response: {}", e))?;
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
            let _ = stream
                .write_all(google_error_html().as_bytes())
                .await;
            return Err(format!("Sign-in was cancelled or access was denied: {}", decoded));
        }
    }

    let token = query
        .split('&')
        .find(|p| p.starts_with("token="))
        .and_then(|p| p.strip_prefix("token="))
        .map(|t| {
            urlencoding::decode(t)
                .map(|d| d.to_string())
                .unwrap_or_else(|_| t.to_string())
        })
        .ok_or_else(|| "No login token received from the Google callback.".to_string())?;

    let _ = stream.write_all(google_success_html().as_bytes()).await;
    Ok(token)
}

fn google_success_html() -> &'static str {
    "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n\
     <html><head><meta charset=\"utf-8\">\
     <style>body{font-family:-apple-system,sans-serif;background:#f5f5f7;\
     display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;}\
     .card{background:#fff;border-radius:16px;padding:48px 40px;max-width:420px;\
     text-align:center;box-shadow:0 4px 24px rgba(0,0,0,.08);}\
     h2{margin:0 0 12px;color:#1d1d1f;font-size:22px;font-weight:600;}\
     p{color:#6e6e73;font-size:15px;line-height:1.5;margin:0;}\
     </style></head><body><div class=\"card\">\
     <h2>Connected to Google</h2>\
     <p>You can close this tab and return to Rong-E.</p>\
     </div></body></html>"
}

fn google_error_html() -> &'static str {
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

fn build_expanded_path() -> String {
    let home = dirs::home_dir().unwrap_or_default();
    let home_str = home.to_string_lossy();
    let mut extra_paths: Vec<String> = Vec::new();

    let nvm_dir = home.join(".nvm").join("versions").join("node");
    if let Ok(entries) = std::fs::read_dir(&nvm_dir) {
        for entry in entries.flatten() {
            let bin = entry.path().join("bin");
            if bin.is_dir() {
                extra_paths.push(bin.to_string_lossy().to_string());
            }
        }
    }

    let common_dirs = [
        format!("{}/.local/bin", home_str),
        "/opt/homebrew/bin".to_string(),
        "/usr/local/bin".to_string(),
        "/opt/local/bin".to_string(),
        format!("{}/.cargo/bin", home_str),
        format!("{}/go/bin", home_str),
    ];

    for dir in &common_dirs {
        if std::path::Path::new(dir).is_dir() {
            extra_paths.push(dir.clone());
        }
    }

    let existing = std::env::var("PATH").unwrap_or_default();
    if !existing.is_empty() {
        extra_paths.push(existing);
    }
    extra_paths.join(":")
}

fn resolve_command(command: &str, path: &str) -> String {
    if command.starts_with('/') {
        return command.to_string();
    }
    for dir in path.split(':') {
        let candidate = std::path::Path::new(dir).join(command);
        if candidate.is_file() {
            return candidate.to_string_lossy().to_string();
        }
    }
    command.to_string()
}
