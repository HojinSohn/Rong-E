use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

/// A live MCP server connection.
pub struct McpConnection {
    pub tools: Vec<rmcp::model::Tool>,
    pub peer: rmcp::service::ServerSink,
    /// Must stay alive to keep the peer valid.
    pub _service: rmcp::service::RunningService<rmcp::RoleClient, ()>,
}

pub struct AppState {
    pub current_model: String,
    pub current_provider: String,
    pub api_keys: HashMap<String, String>,
    pub mcp_connections: HashMap<String, McpConnection>,
    pub builtin_servers: HashMap<String, McpConnection>,
    pub composio_api_key: Option<String>,
}

pub type SharedState = Arc<Mutex<AppState>>;

impl AppState {
    pub fn new() -> Self {
        Self {
            current_model: "gemini-2.5-flash".to_string(),
            current_provider: "gemini".to_string(),
            api_keys: HashMap::new(),
            mcp_connections: HashMap::new(),
            builtin_servers: HashMap::new(),
            composio_api_key: None,
        }
    }

    /// Collect all MCP tools + peers for agent building (user-configured + built-in)
    pub fn all_mcp_tools(&self) -> Vec<(Vec<rmcp::model::Tool>, rmcp::service::ServerSink)> {
        self.mcp_connections
            .values()
            .chain(self.builtin_servers.values())
            .map(|c| (c.tools.clone(), c.peer.clone()))
            .collect()
    }
}
