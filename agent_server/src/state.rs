use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

/// A live MCP server connection
pub struct McpConnection {
    pub tools: Vec<rmcp::model::Tool>,
    pub peer: rmcp::service::ServerSink,
    /// Must stay alive to keep the peer valid
    pub _service: rmcp::service::RunningService<rmcp::RoleClient, ()>,
}

pub struct AppState {
    pub current_model: String,
    pub current_provider: String,
    pub api_key: Option<String>,
    pub mcp_connections: HashMap<String, McpConnection>,
}

pub type SharedState = Arc<Mutex<AppState>>;

impl AppState {
    pub fn new() -> Self {
        Self {
            current_model: "gemini-2.5-flash".to_string(),
            current_provider: "gemini".to_string(),
            api_key: None,
            mcp_connections: HashMap::new(),
        }
    }

    /// Collect all MCP tools + peers for agent building
    pub fn all_mcp_tools(&self) -> Vec<(Vec<rmcp::model::Tool>, rmcp::service::ServerSink)> {
        self.mcp_connections
            .values()
            .map(|c| (c.tools.clone(), c.peer.clone()))
            .collect()
    }
}
