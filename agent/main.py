import asyncio
from agent.agent import EchoAgent

async def main():
    agent = EchoAgent()
    print("Echo is ready. Type 'quit' to exit.")
    
    while True:
        user_input = input("You: ")
        if user_input.lower() in ["quit", "exit"]:
            break
        
        await agent.run(user_input)

if __name__ == "__main__":
    asyncio.run(main())
