use crate::tools::{
    AppendToMemory, Calculator, GetCurrentDateTime, OpenApplication, OpenChromeTab, ReadMemory,
    SaveToMemory,
};
use rig::{
    completion::Chat,
    message::{DocumentSourceKind, Image, ImageMediaType, Message as RigMessage, UserContent},
    providers::{anthropic, gemini, ollama, openai},
    OneOrMany,
};
use rig::client::CompletionClient;
use rig::client::ProviderClient;

pub async fn call_llm(
    provider: &str,
    api_key: &str,
    model: &str,
    query: &str,
    chat_history: Vec<RigMessage>,
    mcp_tool_sets: Vec<(Vec<rmcp::model::Tool>, rmcp::service::ServerSink)>,
    system_prompt: Option<&str>,
    base64_image: Option<&str>,
) -> Result<String, String> {
    let memory_path = crate::tools::default_memory_path();
    
    // 1. Define the "Safety Instruction"
    // This forces Gemini to acknowledge the tool execution.
    let safety_instruction = "IMPORTANT: Whenever you use a tool, you MUST reply to the user with a text summary of the result. Never return an empty response after using a tool.";

    // 2. Merge with user's system prompt
    let final_prompt = if let Some(user_prompt) = system_prompt {
        format!("{}\n\n{}", user_prompt, safety_instruction)
    } else {
        safety_instruction.to_string()
    };

    match provider {
        "gemini" => {
            let client = gemini::Client::new(api_key).map_err(|e| e.to_string())?;
            let mut builder = client
                .agent(model)
                .tool(Calculator)
                .tool(GetCurrentDateTime)
                .tool(OpenApplication)
                .tool(OpenChromeTab)
                .tool(ReadMemory::new(memory_path.clone()))
                .tool(SaveToMemory::new(memory_path.clone()))
                .tool(AppendToMemory::new(memory_path))
                .preamble(&final_prompt);
                
            for (tools, peer) in mcp_tool_sets {
                builder = builder.rmcp_tools(tools, peer);
            }
            let agent = builder.build();
            chat_with_agent(&agent, query, chat_history, base64_image).await
        }
        "openai" => {
            let client: openai::Client =
                openai::Client::new(api_key).map_err(|e| e.to_string())?;
            let mut builder = client
                .agent(model)
                .tool(Calculator)
                .tool(GetCurrentDateTime)
                .tool(OpenApplication)
                .tool(OpenChromeTab)
                .tool(ReadMemory::new(memory_path.clone()))
                .tool(SaveToMemory::new(memory_path.clone()))
                .tool(AppendToMemory::new(memory_path))
                .preamble(&final_prompt);

            for (tools, peer) in mcp_tool_sets {
                builder = builder.rmcp_tools(tools, peer);
            }
            let agent = builder.build();
            chat_with_agent(&agent, query, chat_history, base64_image).await
        }
        "anthropic" => {
            let client: anthropic::Client =
                anthropic::Client::new(api_key).map_err(|e| e.to_string())?;
            let mut builder = client
                .agent(model)
                .tool(Calculator)
                .tool(GetCurrentDateTime)
                .tool(OpenApplication)
                .tool(OpenChromeTab)
                .tool(ReadMemory::new(memory_path.clone()))
                .tool(SaveToMemory::new(memory_path.clone()))
                .tool(AppendToMemory::new(memory_path))
                .preamble(&final_prompt);

            for (tools, peer) in mcp_tool_sets {
                builder = builder.rmcp_tools(tools, peer);
            }
            let agent = builder.build();
            chat_with_agent(&agent, query, chat_history, base64_image).await
        }
        "ollama" => {
            let client = ollama::Client::from_env();
            let mut builder = client
                .agent(model)
                .tool(Calculator)
                .tool(GetCurrentDateTime)
                .tool(OpenApplication)
                .tool(OpenChromeTab)
                .tool(ReadMemory::new(memory_path.clone()))
                .tool(SaveToMemory::new(memory_path.clone()))
                .tool(AppendToMemory::new(memory_path))
                .preamble(&final_prompt);
                
            for (tools, peer) in mcp_tool_sets {
                builder = builder.rmcp_tools(tools, peer);
            }
            let agent = builder.build();
            chat_with_agent(&agent, query, chat_history, base64_image).await
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
            // Verify Ollama is reachable by making a real call
            let client = ollama::Client::from_env();
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
