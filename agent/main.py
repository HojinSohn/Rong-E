from agent import EchoAgent

if __name__ == "__main__":
    agent = EchoAgent()
    print("Echo is ready. Type 'quit' to exit.")
    
    while True:
        user_input = input("You: ")
        if user_input.lower() in ["quit", "exit"]:
            break
        
        agent.run(user_input)
