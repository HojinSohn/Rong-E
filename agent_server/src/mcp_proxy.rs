use crate::tools::ToolEventSender;
use rmcp::{
    serve_client, serve_server, ServerHandler,
    model::{CallToolRequestParam, CallToolResult, ErrorData, ListToolsResult, PaginatedRequestParam},
    service::{Peer, RequestContext, RoleClient, RoleServer},
};
use serde_json::json;
use std::borrow::Cow;
use std::collections::HashMap;

/// Sanitise an MCP tool name so it is accepted by **all** LLM providers.
///
/// Gemini requires: starts with a letter or `_`, only `[a-zA-Z0-9_.\-:]`, max 64 chars.
/// We replace every disallowed character with `_` and, if the name starts with a
/// digit, prepend `_`.
pub fn sanitize_tool_name(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    for ch in raw.chars() {
        if ch.is_ascii_alphanumeric() || ch == '_' || ch == '.' || ch == '-' || ch == ':' {
            out.push(ch);
        } else {
            out.push('_');
        }
    }
    // Must start with a letter or underscore
    if out.starts_with(|c: char| c.is_ascii_digit() || c == '.' || c == '-' || c == ':') {
        out.insert(0, '_');
    }
    // Max 64 characters
    out.truncate(64);
    out
}

/// An in-process MCP server that sits between rig and a real MCP server peer.
/// It fires `tool_call` / `tool_result` WS events whenever a tool is invoked.
pub struct NotifyingMcpProxy {
    real_peer: Peer<RoleClient>,
    /// Tools with **sanitized** names (safe for all LLM providers).
    tools: Vec<rmcp::model::Tool>,
    /// Maps sanitized name → original MCP name for forwarding calls.
    name_map: HashMap<String, String>,
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
        let sanitized_name = request.name.to_string();

        // Resolve back to the original MCP name for forwarding
        let original_name = self
            .name_map
            .get(&sanitized_name)
            .cloned()
            .unwrap_or_else(|| sanitized_name.clone());

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
                "content": { "toolName": &sanitized_name, "toolArgs": args_json }
            }))
            .await;

        // Forward to the real MCP server using the **original** name
        let forwarded = CallToolRequestParam {
            name: Cow::Owned(original_name),
            arguments: request.arguments,
            task: request.task,
        };
        let result = self
            .real_peer
            .call_tool(forwarded)
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
                "content": { "toolName": &sanitized_name, "result": result_str }
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
/// - The sanitized tool list (safe for all LLM providers) to pass to `builder.rmcp_tools()`
/// - The proxy peer to pass to `builder.rmcp_tools()`
/// - A `McpProxyGuard` that **must stay alive** for the duration of the agent call
pub async fn create_notifying_proxy(
    tools: Vec<rmcp::model::Tool>,
    real_peer: Peer<RoleClient>,
    tx: ToolEventSender,
) -> Result<(Vec<rmcp::model::Tool>, Peer<RoleClient>, McpProxyGuard), String> {
    let (server_io, client_io) = tokio::io::duplex(4096);

    // Build sanitized tools + reverse mapping
    let mut name_map: HashMap<String, String> = HashMap::new();
    let sanitized_tools: Vec<rmcp::model::Tool> = tools
        .into_iter()
        .map(|mut t| {
            let original = t.name.to_string();
            let safe = sanitize_tool_name(&original);
            if safe != original {
                println!("🔧 MCP tool name sanitized: '{}' → '{}'", original, safe);
                name_map.insert(safe.clone(), original);
                t.name = Cow::Owned(safe);
            }
            t
        })
        .collect();

    let proxy_handler = NotifyingMcpProxy {
        real_peer,
        tools: sanitized_tools.clone(),
        name_map,
        tx,
    };

    // Server and client must handshake concurrently — join! prevents deadlock
    let (server_result, client_result) =
        tokio::join!(serve_server(proxy_handler, server_io), serve_client((), client_io));

    let proxy_server = server_result.map_err(|e| format!("MCP proxy server: {e}"))?;
    let proxy_client = client_result.map_err(|e| format!("MCP proxy client: {e}"))?;

    let proxy_peer = proxy_client.peer().clone();

    Ok((
        sanitized_tools,
        proxy_peer,
        McpProxyGuard {
            server: proxy_server,
            client: proxy_client,
        },
    ))
}
