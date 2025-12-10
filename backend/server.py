from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
from agent import EchoAgent
import uvicorn

app = FastAPI()

# Allow CORS for the frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize agent
agent = EchoAgent()

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

def get_agent():
    return agent

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
