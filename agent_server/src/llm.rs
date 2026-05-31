use crate::tools::{
    AddMemoryNode, Calculator, DeleteMemoryNode, LinkMemories, NotifyingTool,
    OpenApplication, OpenChromeTab, QueryMemories, ToolEventSender, UpdateMemoryNode,
};
use rig::{
    completion::Chat,
    message::{DocumentSourceKind, Image, ImageMediaType, Message as RigMessage, UserContent},
    providers::{anthropic, gemini, ollama, openai},
    OneOrMany,
};
use rig::client::CompletionClient;
use rig::client::ProviderClient;

const MEMORY_CHECK_IN: &str = "\
### Memory Check-In (required)
After responding, review this conversation turn. If the user shared anything worth \
remembering (preferences, facts, project context, people, dates, decisions), call \
add_memory_node immediately. If an existing memory is now outdated, call \
update_memory_node. If nothing new was shared, do nothing.";

const SYSTEM_PROMPT_TEMPLATE: &str = include_str!("../prompts/system_prompt.txt");

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
    tool_tx: ToolEventSender,
    user_name: Option<String>,
    graph_memory: std::sync::Arc<crate::graph_memory::GraphMemory>,
) -> Result<String, String> {

    let user_name = user_name
        .filter(|n| !n.is_empty())
        .unwrap_or_else(|| std::env::var("USER").unwrap_or_else(|_| "User".to_string()));

    let now = chrono::Local::now();
    let current_datetime = now.format("%A, %B %-d, %Y %H:00").to_string();

    let base_prompt = SYSTEM_PROMPT_TEMPLATE
        .replace("{user_name}", &user_name)
        .replace("{current_datetime}", &current_datetime);

    let final_prompt = if let Some(ref mode_prompt) = system_prompt {
        format!("{}\n\n{}", base_prompt, mode_prompt)
    } else {
        base_prompt
    };

    let memory_context = {
        let g = std::sync::Arc::clone(&graph_memory);
        let q = query.clone();
        tokio::task::spawn_blocking(move || {
            crate::graph_memory::retrieve_relevant_memories(&q, &g)
        })
        .await
        .unwrap_or_default()
    };

    // Shadow final_prompt to append memory context and mandatory check-in instruction
    let final_prompt = if memory_context.is_empty() {
        format!("{}\n\n{}", final_prompt, MEMORY_CHECK_IN)
    } else {
        format!("{}\n\n{}\n\n{}", final_prompt, memory_context, MEMORY_CHECK_IN)
    };

    println!("🧠 Final system prompt:\n{}", final_prompt);

    // Wrap each MCP connection with a notification proxy so tool_call/tool_result
    // events are emitted for MCP tools.
    let mut _proxy_guards: Vec<crate::mcp_proxy::McpProxyGuard> = Vec::new();
    let mut proxied_mcp_tool_sets: Vec<(Vec<rmcp::model::Tool>, rmcp::service::ServerSink)> =
        Vec::new();
    for (tools, peer) in mcp_tool_sets {
        match crate::mcp_proxy::create_notifying_proxy(tools, peer, tool_tx.clone()).await {
            Ok((sanitized_tools, proxy_peer, guard)) => {
                proxied_mcp_tool_sets.push((sanitized_tools, proxy_peer));
                _proxy_guards.push(guard);
            }
            Err(e) => {
                println!("⚠️ MCP notification proxy failed (tool events skipped): {}", e);
            }
        }
    }

    macro_rules! build_agent {
        ($builder_expr:expr) => {{
            let tx = &tool_tx;
            let mut builder = $builder_expr
                .tool(NotifyingTool { inner: Calculator, tx: tx.clone() })
                .tool(NotifyingTool { inner: OpenApplication, tx: tx.clone() })
                .tool(NotifyingTool { inner: OpenChromeTab, tx: tx.clone() })
                .tool(NotifyingTool { inner: AddMemoryNode::new(std::sync::Arc::clone(&graph_memory)), tx: tx.clone() })
                .tool(NotifyingTool { inner: QueryMemories::new(std::sync::Arc::clone(&graph_memory)), tx: tx.clone() })
                .tool(NotifyingTool { inner: UpdateMemoryNode::new(std::sync::Arc::clone(&graph_memory)), tx: tx.clone() })
                .tool(NotifyingTool { inner: LinkMemories::new(std::sync::Arc::clone(&graph_memory)), tx: tx.clone() })
                .tool(NotifyingTool { inner: DeleteMemoryNode::new(std::sync::Arc::clone(&graph_memory)), tx: tx.clone() })
                .preamble(&final_prompt);
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
        "openrouter" => {
            let client: openai::Client<reqwest::Client> = openai::Client::builder()
                .api_key(api_key.clone())
                .base_url("https://openrouter.ai/api/v1")
                .build()
                .map_err(|e| e.to_string())?;
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
                    "Ollama doesn't appear to be running. Please start it with `ollama serve`."
                        .to_string(),
                ),
            }
        }
        "openrouter" => {
            let client: openai::Client<reqwest::Client> = openai::Client::builder()
                .api_key(api_key)
                .base_url("https://openrouter.ai/api/v1")
                .build()
                .map_err(|e| e.to_string())?;
            let agent = client.agent(model).build();
            agent.chat(ping, vec![]).await.map(|_| ()).map_err(|e| e.to_string())
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

    // Clone history so we can retry if the agent returns an empty synthesis.
    let history_retry = history.clone();

    let needs_retry = |result: &Result<String, String>| -> bool {
        match result {
            Ok(text) => text.trim().is_empty(),
            Err(e) => e.contains("empty"),
        }
    };

    let first = agent.chat(new_message, history).await.map_err(|e| e.to_string());

    if !needs_retry(&first) {
        return first;
    }

    println!("⚠️ LLM returned empty response after tool execution — retrying for synthesis");
    let retry_message = RigMessage::User {
        content: OneOrMany::one(UserContent::text(
            "You just executed one or more tools. Now write your complete response. \
             Include the actual content you retrieved — do not say 'Done' or leave the response empty.",
        )),
    };
    agent.chat(retry_message, history_retry).await.map_err(|e| e.to_string())
}
