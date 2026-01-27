import asyncio
from agent.agents import RongEAgent

async def main():
    agent = RongEAgent()
    print("RongE is ready. Type 'quit' to exit.")
    config = {
        "mcpServers": {
            "filesystem": {
                "command": "npx",
                "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
            }
        }
    }

    query, mode, base64_image = "Read the most recent email from my gmail", None, None
    agent_callback = None

    await agent.sync_mcp_servers(config)

    # --- 2. Run Agent with Callback ---
    # We await the agent, passing our new function
    final_response = await agent.run(query, mode, base64_image=base64_image, callback=agent_callback)

    # Print final response
    print(f"Final Response: {final_response}")

if __name__ == "__main__":
    asyncio.run(main())
