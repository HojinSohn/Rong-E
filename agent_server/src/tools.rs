use rig::completion::ToolDefinition;
use rig::tool::Tool;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::sync::mpsc;

// ── Tool Event Channel ──

/// Sender half of the tool-event channel.  Clone one per tool instance.
pub type ToolEventSender = mpsc::Sender<serde_json::Value>;

/// Wraps any `Tool` and fires `tool_call` / `tool_result` WebSocket events
/// on `tx` whenever the tool is invoked.
pub struct NotifyingTool<T> {
    pub inner: T,
    pub tx: ToolEventSender,
}

impl<T: Tool> Tool for NotifyingTool<T>
where
    T::Args: Serialize,
    T::Output: Send,
{
    const NAME: &'static str = T::NAME;
    type Args = T::Args;
    type Output = T::Output;
    type Error = T::Error;

    async fn definition(&self, prompt: String) -> ToolDefinition {
        self.inner.definition(prompt).await
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        // Serialize args before they are consumed by the inner call
        let args_json = serde_json::to_value(&args)
            .unwrap_or(serde_json::Value::Object(Default::default()));

        // Notify UI: tool is starting
        // Schema matches Swift ToolCallContent { toolName, toolArgs }
        let _ = self
            .tx
            .send(serde_json::json!({
                "type": "tool_call",
                "content": {
                    "toolName": T::NAME,
                    "toolArgs": args_json
                }
            }))
            .await;

        let result = self.inner.call(args).await?;

        // Notify UI: tool finished
        // Schema matches Swift ToolResultContent { toolName, result }
        if let Ok(result_str) = serde_json::to_string(&result) {
            const MAX_RESULT_BYTES: usize = 32 * 1024; // 32 KB
            let result_str = if result_str.len() > MAX_RESULT_BYTES {
                format!(
                    "{}... [truncated — {} bytes total]",
                    &result_str[..MAX_RESULT_BYTES],
                    result_str.len()
                )
            } else {
                result_str
            };
            let _ = self
                .tx
                .send(serde_json::json!({
                    "type": "tool_result",
                    "content": {
                        "toolName": T::NAME,
                        "result": result_str
                    }
                }))
                .await;
        }

        Ok(result)
    }
}

// ── Error Types ──

#[derive(Debug, Error)]
pub enum ToolError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Command failed: {0}")]
    CommandFailed(String),
    #[error("{0}")]
    Other(String),
}

// ── Calculator ──

#[derive(Deserialize, Serialize)]
pub struct CalcArgs {
    x: f64,
    y: f64,
    operation: String,
}

#[derive(Debug, Error)]
#[error("Math error")]
pub struct MathError;

#[derive(Deserialize, Serialize)]
pub struct Calculator;

impl Tool for Calculator {
    const NAME: &'static str = "calculator";
    type Args = CalcArgs;
    type Output = f64;
    type Error = MathError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "calculator".to_string(),
            description: "Performs basic math operations (add, subtract, multiply, divide)".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "x": { "type": "number", "description": "First number" },
                    "y": { "type": "number", "description": "Second number" },
                    "operation": { "type": "string", "enum": ["add", "subtract", "multiply", "divide"] }
                },
                "required": ["x", "y", "operation"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        match args.operation.as_str() {
            "add" => Ok(args.x + args.y),
            "subtract" => Ok(args.x - args.y),
            "multiply" => Ok(args.x * args.y),
            "divide" => Ok(args.x / args.y),
            _ => Ok(0.0),
        }
    }
}

#[derive(Deserialize, Serialize)]
pub struct EmptyArgs {}

// ── OpenApplication ──

#[derive(Deserialize, Serialize)]
pub struct OpenApplication;

#[derive(Deserialize, Serialize)]
pub struct OpenApplicationArgs {
    app_name: String,
}

impl Tool for OpenApplication {
    const NAME: &'static str = "open_application";
    type Args = OpenApplicationArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "open_application".to_string(),
            description: "Opens a specified application on macOS (e.g. Safari, Spotify, Terminal).".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "app_name": { "type": "string", "description": "Name of the application to open" }
                },
                "required": ["app_name"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let status = tokio::process::Command::new("open")
            .arg("-a")
            .arg(&args.app_name)
            .status()
            .await?;

        if !status.success() {
            return Err(ToolError::CommandFailed(format!("Could not open '{}'. Make sure the app is installed on this Mac.", args.app_name)));
        }

        let _ = tokio::process::Command::new("osascript")
            .arg("-e")
            .arg(format!("activate application \"{}\"", args.app_name))
            .status()
            .await;

        Ok(format!("Opened {}", args.app_name))
    }
}

// ── OpenChromeTab ──

#[derive(Deserialize, Serialize)]
pub struct OpenChromeTab;

#[derive(Deserialize, Serialize)]
pub struct OpenChromeTabArgs {
    url: String,
}

impl Tool for OpenChromeTab {
    const NAME: &'static str = "open_chrome_tab";
    type Args = OpenChromeTabArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "open_chrome_tab".to_string(),
            description: "Opens a URL in a new tab in Google Chrome.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "url": { "type": "string", "description": "The URL to open" }
                },
                "required": ["url"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let script = format!(
            r#"tell application "Google Chrome"
    activate
    if (count every window) = 0 then
        make new window
    end if
    tell window 1
        make new tab with properties {{URL:"{}"}}
    end tell
end tell"#,
            args.url
        );

        let status = tokio::process::Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .status()
            .await?;

        if !status.success() {
            return Err(ToolError::CommandFailed("Could not open the URL in Chrome. Make sure Google Chrome is installed.".into()));
        }

        Ok(format!("Opened {} in Chrome", args.url))
    }
}

use std::sync::Arc;
use crate::graph_memory::GraphMemory;

// ── Graph Memory Tools ──

// AddMemoryNode

#[derive(Clone)]
pub struct AddMemoryNode {
    pub graph: Arc<GraphMemory>,
}

impl AddMemoryNode {
    pub fn new(graph: Arc<GraphMemory>) -> Self {
        Self { graph }
    }
}

#[derive(Deserialize, Serialize)]
pub struct AddMemoryNodeArgs {
    pub node_type: String,
    pub content: String,
    pub tags: Vec<String>,
    pub related_to: Option<Vec<String>>,
}

impl Tool for AddMemoryNode {
    const NAME: &'static str = "add_memory_node";
    type Args = AddMemoryNodeArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "add_memory_node".to_string(),
            description: "Store a new piece of information as a typed, tagged graph node. Returns the node ID.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "node_type": {
                        "type": "string",
                        "enum": ["preference", "person", "project", "event", "fact", "context"],
                        "description": "Category of this memory"
                    },
                    "content": { "type": "string", "description": "The memory text to store" },
                    "tags": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "Keywords for retrieval, e.g. [\"rust\", \"deadline\", \"work\"]"
                    },
                    "related_to": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "Optional IDs of existing nodes to link with related_to edges"
                    }
                },
                "required": ["node_type", "content", "tags"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let graph = Arc::clone(&self.graph);
        let node_type = args.node_type.clone();
        let content = args.content.clone();
        let tags = args.tags.clone();
        let related_to = args.related_to.clone();
        let id = tokio::task::spawn_blocking(move || {
            graph.add_node(&node_type, &content, &tags)
        })
        .await
        .map_err(|e| ToolError::Other(e.to_string()))?
        .map_err(|e| ToolError::Other(e.to_string()))?;

        if let Some(related_ids) = related_to {
            let graph2 = Arc::clone(&self.graph);
            let id2 = id.clone();
            tokio::task::spawn_blocking(move || {
                for rel_id in &related_ids {
                    let _ = graph2.link_nodes(&id2, rel_id, "related_to");
                }
            })
            .await
            .ok();
        }
        Ok(format!("Saved. Node ID: {}", id))
    }
}

// QueryMemories

#[derive(Clone)]
pub struct QueryMemories {
    pub graph: Arc<GraphMemory>,
}

impl QueryMemories {
    pub fn new(graph: Arc<GraphMemory>) -> Self {
        Self { graph }
    }
}

#[derive(Deserialize, Serialize)]
pub struct QueryMemoriesArgs {
    pub keywords: Vec<String>,
    pub node_type: Option<String>,
    pub limit: Option<usize>,
}

impl Tool for QueryMemories {
    const NAME: &'static str = "query_memories";
    type Args = QueryMemoriesArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "query_memories".to_string(),
            description: "Search memory nodes by keyword tags. Returns matching nodes with their IDs.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "keywords": {
                        "type": "array",
                        "items": { "type": "string" },
                        "description": "Tags to search for"
                    },
                    "node_type": {
                        "type": "string",
                        "description": "Optional filter by type"
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Max results (default 10)"
                    }
                },
                "required": ["keywords"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let graph = Arc::clone(&self.graph);
        let keywords = args.keywords;
        let node_type = args.node_type.clone();
        let limit = args.limit.unwrap_or(10);
        let nodes = tokio::task::spawn_blocking(move || {
            graph.query_by_keywords(&keywords, node_type.as_deref(), limit)
        })
        .await
        .map_err(|e| ToolError::Other(e.to_string()))?
        .map_err(|e| ToolError::Other(e.to_string()))?;

        if nodes.is_empty() {
            return Ok("No matching memories found.".to_string());
        }
        Ok(crate::graph_memory::format_for_prompt(&nodes))
    }
}

// UpdateMemoryNode

#[derive(Clone)]
pub struct UpdateMemoryNode {
    pub graph: Arc<GraphMemory>,
}

impl UpdateMemoryNode {
    pub fn new(graph: Arc<GraphMemory>) -> Self {
        Self { graph }
    }
}

#[derive(Deserialize, Serialize)]
pub struct UpdateMemoryNodeArgs {
    pub id: String,
    pub content: Option<String>,
    pub tags: Option<Vec<String>>,
    pub node_type: Option<String>,
}

impl Tool for UpdateMemoryNode {
    const NAME: &'static str = "update_memory_node";
    type Args = UpdateMemoryNodeArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "update_memory_node".to_string(),
            description: "Patch an existing memory node by ID. Use instead of creating duplicates.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "id": { "type": "string", "description": "Node ID to update" },
                    "content": { "type": "string" },
                    "tags": { "type": "array", "items": { "type": "string" } },
                    "node_type": { "type": "string" }
                },
                "required": ["id"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let graph = Arc::clone(&self.graph);
        let id = args.id.clone();
        let content = args.content.clone();
        let tags = args.tags.clone();
        let node_type = args.node_type.clone();
        tokio::task::spawn_blocking(move || {
            graph.update_node(
                &id,
                content.as_deref(),
                tags.as_deref(),
                node_type.as_deref(),
            )
        })
        .await
        .map_err(|e| ToolError::Other(e.to_string()))?
        .map_err(|e| ToolError::Other(e.to_string()))?;
        Ok("Memory node updated.".to_string())
    }
}

// LinkMemories

#[derive(Clone)]
pub struct LinkMemories {
    pub graph: Arc<GraphMemory>,
}

impl LinkMemories {
    pub fn new(graph: Arc<GraphMemory>) -> Self {
        Self { graph }
    }
}

#[derive(Deserialize, Serialize)]
pub struct LinkMemoriesArgs {
    pub from_id: String,
    pub to_id: String,
    pub relationship: String,
}

impl Tool for LinkMemories {
    const NAME: &'static str = "link_memories";
    type Args = LinkMemoriesArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "link_memories".to_string(),
            description: "Create a directed relationship edge between two memory nodes.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "from_id": { "type": "string" },
                    "to_id": { "type": "string" },
                    "relationship": {
                        "type": "string",
                        "description": "e.g. related_to, part_of, depends_on, contradicts"
                    }
                },
                "required": ["from_id", "to_id", "relationship"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let graph = Arc::clone(&self.graph);
        let from_id = args.from_id.clone();
        let to_id = args.to_id.clone();
        let relationship = args.relationship.clone();
        tokio::task::spawn_blocking(move || {
            graph.link_nodes(&from_id, &to_id, &relationship)
        })
        .await
        .map_err(|e| ToolError::Other(e.to_string()))?
        .map_err(|e| ToolError::Other(e.to_string()))?;
        Ok(format!("Linked {} → {} as {}.", args.from_id, args.to_id, args.relationship))
    }
}

// DeleteMemoryNode

#[derive(Clone)]
pub struct DeleteMemoryNode {
    pub graph: Arc<GraphMemory>,
}

impl DeleteMemoryNode {
    pub fn new(graph: Arc<GraphMemory>) -> Self {
        Self { graph }
    }
}

#[derive(Deserialize, Serialize)]
pub struct DeleteMemoryNodeArgs {
    pub id: String,
}

impl Tool for DeleteMemoryNode {
    const NAME: &'static str = "delete_memory_node";
    type Args = DeleteMemoryNodeArgs;
    type Output = String;
    type Error = ToolError;

    async fn definition(&self, _prompt: String) -> ToolDefinition {
        ToolDefinition {
            name: "delete_memory_node".to_string(),
            description: "Remove a memory node and all its edges.".to_string(),
            parameters: serde_json::json!({
                "type": "object",
                "properties": {
                    "id": { "type": "string", "description": "Node ID to delete" }
                },
                "required": ["id"]
            }),
        }
    }

    async fn call(&self, args: Self::Args) -> Result<Self::Output, Self::Error> {
        let graph = Arc::clone(&self.graph);
        let id = args.id.clone();
        tokio::task::spawn_blocking(move || graph.delete_node(&id))
            .await
            .map_err(|e| ToolError::Other(e.to_string()))?
            .map_err(|e| ToolError::Other(e.to_string()))?;
        Ok("Memory node deleted.".to_string())
    }
}
