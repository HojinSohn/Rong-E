use crate::google_agent::GoogleSubAgent;
use crate::tools::{
    AppendToMemory, Calculator, NotifyingTool, OpenApplication, OpenChromeTab,
    ReadMemory, SaveToMemory, ToolEventSender,
};
use rig::{
    completion::Chat,
    message::{DocumentSourceKind, Image, ImageMediaType, Message as RigMessage, UserContent},
    providers::{anthropic, gemini, ollama, openai},
    OneOrMany,
};
use rig::client::CompletionClient;
use rig::client::ProviderClient;

/// Base personality / instructions for the main Rong-E agent.
/// Embedded at compile time so the binary is self-contained.
const SYSTEM_PROMPT_TEMPLATE: &str =
    include_str!("../prompts/system_prompt.txt");

#[allow(clippy::too_many_arguments)]
pub async fn call_llm(
    provider: String,
    api_key: String,
    model: String,
    query: String,
    chat_history: Vec<RigMessage>,
    mcp_tool_sets: Vec<(Vec<rmcp::model::Tool>, rmcp::service::ServerSink)>,
    system_prompt: Option<String>,
    base64_image: Option<String>,
    google_access_token: Option<String>,
    spreadsheet_configs: Vec<crate::state::SpreadsheetConfig>,
    tool_tx: ToolEventSender,
    user_name: Option<String>,
) -> Result<String, String> {
    let memory_path = crate::tools::default_memory_path();

    // Use the name provided by the Swift UI; fall back to the OS login name.
    let user_name = user_name
        .filter(|n| !n.is_empty())
        .unwrap_or_else(|| std::env::var("USER").unwrap_or_else(|_| "User".to_string()));

    // Current date/time injected at call time so the LLM always has it.
    let now = chrono::Local::now();
    let current_datetime = now.format("%A, %B %-d, %Y %H:00").to_string();

    let base_prompt = SYSTEM_PROMPT_TEMPLATE
        .replace("{user_name}", &user_name)
        .replace("{current_datetime}", &current_datetime);

    // Build the spreadsheet context block — alias + description only.
    // The google_agent sub-agent holds the alias→ID map; this agent only needs
    // to know which names exist so it can route requests correctly.
    let spreadsheet_context = if spreadsheet_configs.is_empty() {
        String::new()
    } else {
        let mut lines = vec![
            "\n\n## Available Google Spreadsheets".to_string(),
            "The user has registered the following spreadsheets by alias. When they mention one, delegate the task to google_agent using the alias name — the sub-agent will resolve it to the correct spreadsheet ID.".to_string(),
        ];
        for cfg in &spreadsheet_configs {
            let desc_info = if cfg.description.is_empty() {
                String::new()
            } else {
                format!(" — {}", cfg.description)
            };
            lines.push(format!("- **{}**{}", cfg.alias, desc_info));
        }
        lines.join("\n")
    };

    // Build the final preamble: base personality → spreadsheet context → optional mode prompt
    let final_prompt = if let Some(ref mode_prompt) = system_prompt {
        format!("{}{}\n\n{}", base_prompt, spreadsheet_context, mode_prompt)
    } else {
        format!("{}{}", base_prompt, spreadsheet_context)
    };

    println!("🧠 Final system prompt:\n{}", final_prompt);

    // Wrap each MCP connection with an in-process notification proxy so that
    // tool_call / tool_result events are emitted for MCP tools too.
    let mut _proxy_guards: Vec<crate::mcp_proxy::McpProxyGuard> = Vec::new();
    let mut proxied_mcp_tool_sets: Vec<(Vec<rmcp::model::Tool>, rmcp::service::ServerSink)> =
        Vec::new();
    for (tools, peer) in mcp_tool_sets {
        match crate::mcp_proxy::create_notifying_proxy(tools.clone(), peer, tool_tx.clone()).await {
            Ok((proxy_peer, guard)) => {
                proxied_mcp_tool_sets.push((tools, proxy_peer));
                _proxy_guards.push(guard);
            }
            Err(e) => {
                println!("⚠️ MCP notification proxy failed (tool events skipped): {}", e);
            }
        }
    }

    // Helper macro so we don't duplicate the builder setup across providers
    macro_rules! build_agent {
        ($builder_expr:expr) => {{
            let tx = &tool_tx;
            let mut builder = $builder_expr
                .tool(NotifyingTool { inner: Calculator, tx: tx.clone() })
                .tool(NotifyingTool { inner: OpenApplication, tx: tx.clone() })
                .tool(NotifyingTool { inner: OpenChromeTab, tx: tx.clone() })
                .tool(NotifyingTool { inner: ReadMemory::new(memory_path.clone()), tx: tx.clone() })
                .tool(NotifyingTool { inner: SaveToMemory::new(memory_path.clone()), tx: tx.clone() })
                .tool(NotifyingTool { inner: AppendToMemory::new(memory_path.clone()), tx: tx.clone() })
                .preamble(&final_prompt);
            if let Some(ref token) = google_access_token {
                builder = builder.tool(NotifyingTool {
                    inner: GoogleSubAgent::new(
                        token.clone(),
                        api_key.clone(),
                        provider.clone(),
                        model.clone(),
                        spreadsheet_configs.clone(),
                    ),
                    tx: tx.clone(),
                });
            }
            for (tools, peer) in proxied_mcp_tool_sets {
                builder = builder.rmcp_tools(tools, peer);
            }
            builder.default_max_turns(15).build()
        }};
    }

    match provider.as_str() {
        "gemini" => {
            let client = gemini::Client::new(&api_key).map_err(|e| e.to_string())?;
            let agent = build_agent!(client.agent(&model));
            chat_with_agent(&agent, &query, chat_history, base64_image.as_deref()).await
        }
        "openai" => {
            let client: openai::Client =
                openai::Client::new(&api_key).map_err(|e| e.to_string())?;
            let agent = build_agent!(client.agent(&model));
            chat_with_agent(&agent, &query, chat_history, base64_image.as_deref()).await
        }
        "anthropic" => {
            let client: anthropic::Client =
                anthropic::Client::new(&api_key).map_err(|e| e.to_string())?;
            let agent = build_agent!(client.agent(&model));
            chat_with_agent(&agent, &query, chat_history, base64_image.as_deref()).await
        }
        "ollama" => {
            let client = ollama::Client::from_env();
            let agent = build_agent!(client.agent(&model));
            chat_with_agent(&agent, &query, chat_history, base64_image.as_deref()).await
        }
        _ => Err(format!("Unsupported provider: {}", provider)),
    }
}

/// Makes a minimal test call to verify the provider/model/key combination is valid.
pub async fn verify_llm(provider: &str, api_key: &str, model: &str) -> Result<(), String> {
    let ping = RigMessage::User {
        content: OneOrMany::one(UserContent::text("Hi")),
    };
    match provider {
        "gemini" => {
            let client = gemini::Client::new(api_key).map_err(|e| e.to_string())?;
            let agent = client.agent(model).build();
            agent.chat(ping, vec![]).await.map(|_| ()).map_err(|e| e.to_string())
        }
        "openai" => {
            let client: openai::Client = openai::Client::new(api_key).map_err(|e| e.to_string())?;
            let agent = client.agent(model).build();
            agent.chat(ping, vec![]).await.map(|_| ()).map_err(|e| e.to_string())
        }
        "anthropic" => {
            let client: anthropic::Client =
                anthropic::Client::new(api_key).map_err(|e| e.to_string())?;
            let agent = client.agent(model).build();
            agent.chat(ping, vec![]).await.map(|_| ()).map_err(|e| e.to_string())
        }
        "ollama" => {
            // Check if Ollama is reachable before making a real API call.
            // The rig client has no built-in timeout, so a missing Ollama would
            // hang forever.  A quick TCP probe on the default port lets us fail
            // fast with an actionable message.
            let ollama_addr = std::env::var("OLLAMA_HOST")
                .unwrap_or_else(|_| "127.0.0.1:11434".to_string());
            let reachable = tokio::time::timeout(
                std::time::Duration::from_secs(3),
                tokio::net::TcpStream::connect(&ollama_addr),
            )
            .await;
            match reachable {
                Ok(Ok(_)) => {
                    let client = ollama::Client::from_env();
                    let agent = client.agent(model).build();
                    agent.chat(ping, vec![]).await.map(|_| ()).map_err(|e| e.to_string())
                }
                _ => Err(
                    "Ollama is not running. Download and install it from https://ollama.com, \
                     then start it with `ollama serve`."
                        .to_string(),
                ),
            }
        }
        _ => Err(format!("Unsupported provider: {}", provider)),
    }
}

async fn chat_with_agent(
    agent: &impl Chat,
    query: &str,
    history: Vec<RigMessage>,
    base64_image: Option<&str>,
) -> Result<String, String> {
    let new_message = if let Some(img_data) = base64_image {
        if !img_data.is_empty() {
            let image = Image {
                data: DocumentSourceKind::base64(img_data),
                media_type: Some(ImageMediaType::PNG),
                ..Default::default()
            };
            let content = OneOrMany::many(vec![
                UserContent::text(query),
                UserContent::Image(image),
            ])
            .map_err(|e| e.to_string())?;
            RigMessage::User { content }
        } else {
            RigMessage::User {
                content: OneOrMany::one(UserContent::text(query)),
            }
        }
    } else {
        RigMessage::User {
            content: OneOrMany::one(UserContent::text(query)),
        }
    };

    match agent.chat(new_message, history).await {
        Ok(text) => Ok(text),
        Err(e) => {
            let err_str = e.to_string();
            // rig-core bug: Gemini sometimes returns empty content after tool execution.
            // The tools DID execute, but the LLM's follow-up response was empty.
            // Return a graceful message instead of an error.
            if err_str.contains("empty") {
                println!("⚠️ LLM returned empty response after tool execution (rig-core bug)");
                Ok("I've completed the requested actions. Let me know if you need anything else.".to_string())
            } else {
                Err(err_str)
            }
        }
    }
}


