use crate::tools::ToolEventSender;
use rmcp::{
    serve_client, serve_server, ServerHandler,
    model::{CallToolRequestParam, CallToolResult, ErrorData, ListToolsResult, PaginatedRequestParam},
    service::{Peer, RequestContext, RoleClient, RoleServer},
};
use serde_json::json;

/// An in-process MCP server that sits between rig and a real MCP server peer.
/// It fires `tool_call` / `tool_result` WS events whenever a tool is invoked.
pub struct NotifyingMcpProxy {
    real_peer: Peer<RoleClient>,
    tools: Vec<rmcp::model::Tool>,
    tx: ToolEventSender,
}

impl ServerHandler for NotifyingMcpProxy {
    async fn list_tools(
        &self,
        _request: Option<PaginatedRequestParam>,
        _context: RequestContext<RoleServer>,
    ) -> Result<ListToolsResult, ErrorData> {
        Ok(ListToolsResult::with_all_items(self.tools.clone()))
    }

    async fn call_tool(
        &self,
        request: CallToolRequestParam,
        _context: RequestContext<RoleServer>,
    ) -> Result<CallToolResult, ErrorData> {
        let tool_name = request.name.to_string();

        // Serialize args — matches Swift ToolCallContent { toolName, toolArgs }
        let args_json = request
            .arguments
            .as_ref()
            .map(|m| serde_json::Value::Object(m.clone()))
            .unwrap_or_else(|| serde_json::Value::Object(Default::default()));

        let _ = self
            .tx
            .send(json!({
                "type": "tool_call",
                "content": { "toolName": &tool_name, "toolArgs": args_json }
            }))
            .await;

        // Forward to the real MCP server
        let result = self
            .real_peer
            .call_tool(request)
            .await
            .map_err(|e| ErrorData::internal_error(e.to_string(), None))?;

        // Serialize result — matches Swift ToolResultContent { toolName, result }
        let result_str = serde_json::to_string(&result).unwrap_or_else(|_| String::from("{}"));

        // Truncate very large results so they don't exceed WebSocket frame limits.
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
            .send(json!({
                "type": "tool_result",
                "content": { "toolName": &tool_name, "result": result_str }
            }))
            .await;

        Ok(result)
    }
}

/// Keeps the proxy's in-process services alive for the duration of an LLM call.
/// Dropping this shuts down the proxy.
#[allow(dead_code)]
pub struct McpProxyGuard {
    server: rmcp::service::RunningService<RoleServer, NotifyingMcpProxy>,
    client: rmcp::service::RunningService<RoleClient, ()>,
}

/// Wraps a real MCP peer with an in-process intercepting proxy.
///
/// Returns:
/// - The proxy peer to pass to `builder.rmcp_tools()`
/// - A `McpProxyGuard` that **must stay alive** for the duration of the agent call
pub async fn create_notifying_proxy(
    tools: Vec<rmcp::model::Tool>,
    real_peer: Peer<RoleClient>,
    tx: ToolEventSender,
) -> Result<(Peer<RoleClient>, McpProxyGuard), String> {
    let (server_io, client_io) = tokio::io::duplex(4096);

    let proxy_handler = NotifyingMcpProxy { real_peer, tools, tx };

    // Server and client must handshake concurrently — join! prevents deadlock
    let (server_result, client_result) =
        tokio::join!(serve_server(proxy_handler, server_io), serve_client((), client_io));

    let proxy_server = server_result.map_err(|e| format!("MCP proxy server: {e}"))?;
    let proxy_client = client_result.map_err(|e| format!("MCP proxy client: {e}"))?;

    let proxy_peer = proxy_client.peer().clone();

    Ok((
        proxy_peer,
        McpProxyGuard {
            server: proxy_server,
            client: proxy_client,
        },
    ))
}
