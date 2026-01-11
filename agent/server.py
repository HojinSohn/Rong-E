from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
from agent.agent import EchoAgent
import uvicorn
import json
from agent.utils.audio import speak 
    
app = FastAPI()

# Allow CORS (This handles HTTP requests)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

agent = EchoAgent()
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

            # Normal message processing
            query, mode, base64_image = data["text"], data["mode"], data.get("base64_image")
            print(f"Processing Query: {query} in Mode: {mode}")
            print(f"Base64 Image Present: {'Yes' if base64_image else 'No'}")  
            
            # Callback function to stream responses
            async def agent_callback(type: str, content: str):
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
                elif type == "response": # Final response
                    payload = json.dumps({
                        "type": "response",
                        "content": content
                    })
                if payload:
                    await websocket.send_text(payload)

            print([tool.name for tool in agent.tools])
            print(agent.tool_map.keys())

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