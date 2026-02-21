use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

/// A spreadsheet the user has registered, with an alias the agent can use.
#[derive(Clone, Debug)]
pub struct SpreadsheetConfig {
    pub alias: String,
    pub sheet_id: String,
    pub selected_tab: String,
    pub description: String,
}

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
    pub credentials_file_path: Option<String>,
    pub token_file_path: Option<String>,
    pub google_access_token: Option<String>,
    pub mcp_connections: HashMap<String, McpConnection>,
    pub spreadsheet_configs: Vec<SpreadsheetConfig>,
}

pub type SharedState = Arc<Mutex<AppState>>;

impl AppState {
    pub fn new() -> Self {
        Self {
            current_model: "gemini-2.5-flash".to_string(),
            current_provider: "gemini".to_string(),
            api_key: None,
            credentials_file_path: None,
            token_file_path: None,
            google_access_token: None,
            mcp_connections: HashMap::new(),
            spreadsheet_configs: Vec::new(),
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
