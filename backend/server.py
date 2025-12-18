from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect # <--- Added Imports
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
from backend.agent import EchoAgent
import uvicorn
import json
from backend.utils.audio import speak  # Assuming you have a speak function defined in a separate file
    
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
class ChatRequest(BaseModel):
    message: str
    page_content: str = None
    url: str = None

@app.post("/chat")
async def chat(request: ChatRequest):
    try:
        response = agent.run(request.message, request.page_content, request.url)
        return {"response": response}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 👇 UPDATED WEBSOCKET ENDPOINT@app.websocket("/ws")
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
            query, mode = data["message"], data["mode"]
            print(f"📥 Received: {query} in mode: {mode}")
            
            # --- 1. Define the Callback Function ---
            # This function will be passed to the agent.
            # It sends "thoughts" immediately to the client.
            async def send_thought(thought_text: str):
                payload = json.dumps({
                    "type": "thought",
                    "content": thought_text
                })
                await websocket.send_text(payload)
                speak(f"{thought_text}")  # Optional: Log thoughts to console 

            # --- 2. Run Agent with Callback ---
            # We await the agent, passing our new function
            final_response = await agent.run(query, mode, callback=send_thought)
            
            # --- 3. Send Final Response ---
            final_payload = json.dumps({
                "type": "response",
                "content": final_response
            })
            await websocket.send_text(final_payload)
            speak(f"{final_response}")
            print(f"📤 Sent Final: {final_response}")

    except WebSocketDisconnect:
        print("⚠️ Client disconnected")
    except Exception as e:
        print(f"❌ Error: {e}")
        await websocket.close()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)