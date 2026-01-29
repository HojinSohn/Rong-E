from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
from agent.agents.agent import RongEAgent
from agent.models.mcp_config import validate_mcp_config, MCPConfig
import uvicorn
import json
    
app = FastAPI()

# Allow CORS (This handles HTTP requests)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

agent = RongEAgent()
global_websocket = None

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("✅ Client connected to WebSocket")
    
    try:
        while True:
            # --- 0. Receive Data ---
            #  ["mode": mode, "message": text]
            data = await websocket.receive_text()
            data = json.loads(data)

            # Check if data is credentials
            # check if data_type key exists
            if "data_type" in data:
                if data["data_type"] == "credentials":
                    credentials_dir_path = data["content"]
                    # Here, you would process and store the credentials securely
                    # For demonstration, we just print and acknowledge
                    credentials_file_path = credentials_dir_path + "/credentials.json"
                    token_file_path = credentials_dir_path + "/token.json"
                    print("🔐 Received Credentials")
                    print(f"Credentials Path: {credentials_file_path}")
                    print(f"Token Path: {token_file_path}")
                    try:
                        await agent.authenticate_google(token_file=token_file_path, client_secrets_file=credentials_file_path)
                    except Exception as e:
                        await websocket.send_text(json.dumps({
                            "type": "credentials_error",
                            "content": f"❌ Error during authentication: {str(e)}"
                        }))
                        print(f"❌ Error during authentication: {str(e)}")
                        # Delete token file if exists
                        import os
                        if os.path.exists(token_file_path):
                            os.remove(token_file_path)
                            print("🗑️ Deleted invalid token file.")
                        continue  # Skip the rest of the loop
                    await websocket.send_text(json.dumps({
                        "type": "credentials_success",
                        "content": "✅ Credentials received and stored successfully."
                    }))
                    continue  # Skip the rest of the loop
                elif data["data_type"] == "api_key":
                    api_key_path = data["path"]
                    print("🔑 Received API Key")
                    await websocket.send_text(json.dumps({
                        "type": "credentials_success",
                        "content": "✅ API Key received and stored successfully."
                    }))
                    continue  # Skip the rest of the loop
                elif data["data_type"] == "revoke_credentials":
                    print("🔓 Received Revoke Credentials")
                    agent.revoke_google_credentials()
                    await websocket.send_text(json.dumps({
                        "type": "credentials_revoked",
                        "content": "✅ Credentials revoked successfully."
                    }))
                    continue  # Skip the rest of the loop
                elif data["data_type"] == "mcp_config":
                    print("🔧 Received MCP Config")
                    try:
                        # Validate the config
                        config_data = data.get("config", {})
                        validated_config = validate_mcp_config(config_data)
                        agent_config = validated_config.to_agent_format()

                        # Send "connecting" status for all requested servers
                        requested_names = list(validated_config.mcpServers.keys())
                        connecting_statuses = [
                            {"name": n, "status": "connecting"} for n in requested_names
                        ]
                        await websocket.send_text(json.dumps({
                            "type": "mcp_server_status",
                            "content": {"servers": connecting_statuses}
                        }))

                        # Sync MCP servers and get per-server results
                        results = await agent.sync_mcp_servers(agent_config)

                        # Send final per-server statuses (includes permission_status)
                        final_statuses = [
                            {
                                "name": n,
                                "status": r["status"],
                                "error": r.get("error"),
                                "permission_status": r.get("permission_status", "not_required")
                            }
                            for n, r in results.items()
                        ]
                        await websocket.send_text(json.dumps({
                            "type": "mcp_server_status",
                            "content": {"servers": final_statuses}
                        }))

                        server_count = len(validated_config.mcpServers)
                        server_names = list(validated_config.mcpServers.keys())
                        await websocket.send_text(json.dumps({
                            "type": "mcp_sync_success",
                            "content": f"✅ Synced {server_count} MCP server(s): {', '.join(server_names) if server_names else 'none'}"
                        }))
                    except ValueError as e:
                        await websocket.send_text(json.dumps({
                            "type": "mcp_sync_error",
                            "content": f"❌ Validation error: {str(e)}"
                        }))
                    except Exception as e:
                        print(f"❌ MCP Sync Error: {e}")
                        await websocket.send_text(json.dumps({
                            "type": "mcp_sync_error",
                            "content": f"❌ Failed to sync MCP servers: {str(e)}"
                        }))
                    continue  # Skip the rest of the loop
                elif data["data_type"] == "mcp_status_request":
                    print("📊 Received MCP Status Request")
                    statuses = agent.get_server_statuses()
                    status_list = [
                        {"name": n, "status": s["status"], "error": s.get("error")}
                        for n, s in statuses.items()
                    ]
                    await websocket.send_text(json.dumps({
                        "type": "mcp_server_status",
                        "content": {"servers": status_list}
                    }))
                    continue  # Skip the rest of the loop
                elif data["data_type"] == "reset_session":
                    print("🔄 Received Session Reset Request")
                    agent.reset_session()
                    await websocket.send_text(json.dumps({
                        "type": "session_reset",
                        "content": "Session reset successfully."
                    }))
                    continue
                elif data["data_type"] == "tools_request":
                    print("🔧 Received Tools Request")
                    tools_info = agent.get_active_tools_info()
                    await websocket.send_text(json.dumps({
                        "type": "active_tools",
                        "content": {"tools": tools_info}
                    }))
                    continue

            # Normal message processing
            query, mode, base64_image = data["text"], data["mode"], data.get("base64_image")
            print(f"Processing Query: {query} in Mode: {mode}")
            print(f"Base64 Image Present: {'Yes' if base64_image else 'No'}")  
            
            # Callback function to stream responses
            # content can be:
            #   - str: Simple text content
            #   - dict: Rich content with text, images, and/or widgets
            #           {"text": str, "images": list, "widgets": list}
            async def agent_callback(type: str, content):
                payload = None
                if type == "thought":
                    payload = json.dumps({
                        "type": "thought",
                        "content": content
                    })
                elif type == "tool_call":
                    payload = json.dumps({
                        "type": "tool_call",
                        "content": content
                    })
                elif type == "tool_result":
                    payload = json.dumps({
                        "type": "tool_result",
                        "content": content
                    })
                elif type == "response":
                    # Handle both string and dict content
                    if isinstance(content, dict):
                        # Rich content with widgets
                        payload = json.dumps({
                            "type": "response",
                            "content": {
                                "text": content.get("text", ""),
                                "images": content.get("images", []),
                                "widgets": content.get("widgets", [])
                            }
                        })
                    else:
                        # Simple text response
                        payload = json.dumps({
                            "type": "response",
                            "content": {
                                "text": content,
                                "images": [],
                                "widgets": []
                            }
                        })
                if payload:
                    await websocket.send_text(payload)

            print([tool.name for tool in agent.tools])
            print(agent.tool_map.keys())

            # MCP servers are now configured dynamically via mcp_config messages from the UI
            # No hardcoded config - use MCPConfigView in the SwiftUI app to configure servers

            # --- 2. Run Agent with Callback ---
            # We await the agent, passing our new function
            final_response = await agent.run(query, mode, base64_image=base64_image, callback=agent_callback)

            # Print final response
            print(f"Final Response: {final_response}")

    except WebSocketDisconnect:
        print("⚠️ Client disconnected")
    except Exception as e:
        print(f"❌ Error: {e}")
        await websocket.close()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)