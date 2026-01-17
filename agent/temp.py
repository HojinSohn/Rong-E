
import asyncio
from langchain_google_genai import ChatGoogleGenerativeAI
from mcp_use import MCPAgent, MCPClient
from dotenv import load_dotenv
load_dotenv()

async def main():
    # Configure MCP server
    config = {
        "mcpServers": {
            "filesystem": {
                "command": "npx",
                "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
            }
        }
    }

    client = MCPClient.from_dict(config)
    llm = ChatGoogleGenerativeAI(model="gemini-2.5-flash")
    agent = MCPAgent(llm=llm, client=client)

    result = await agent.run("List all files in the directory")
    print(result)


asyncio.run(main())