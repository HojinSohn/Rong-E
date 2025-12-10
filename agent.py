from langchain_ollama import ChatOllama
from langchain_core.messages import HumanMessage, SystemMessage, ToolMessage
from tools import get_current_time, web_search, record_job_application
from utils import speak

class EchoAgent:
    def __init__(self):
        self.llm = ChatOllama(
            model="qwen2.5:1.5b",
            temperature=0,  # Temperature 0 makes the agent more precise/less random
        )

        # Bind the tools to the model so it knows they exist
        self.tools = [get_current_time, web_search, record_job_application]
        self.llm_with_tools = self.llm.bind_tools(self.tools)

        starting_system_message = "You are an intelligent agent, named Echo, that was born to help me, Hojin Sohn. I, Hojin, am your creator. Use the tools at your disposal to answer my questions."
        self.messages = [SystemMessage(content=starting_system_message)]

    def run(self, user_query):
        print(f"\nUser: {user_query}")
        self.messages.append(HumanMessage(content=user_query))
        
        # Safety: Prevent infinite loops (e.g., if the agent keeps searching forever)
        max_iterations = 5
        iteration = 0

        while iteration < max_iterations:
            iteration += 1
            
            ai_msg = self.llm_with_tools.invoke(self.messages)
            self.messages.append(ai_msg)

            if ai_msg.tool_calls:
                print(f"Agent (Step {iteration}): Thinking... (Calling Tools)")
                
                for tool_call in ai_msg.tool_calls:
                    tool_name = tool_call["name"].lower()
                    tool_args = tool_call["args"]
                    tool_call_id = tool_call["id"]  # Critical for linking result to request
                    
                    # Map names to functions
                    tool_map = {
                        "get_current_time": get_current_time, 
                        "web_search": web_search,
                        "record_job_application": record_job_application
                    }
                    
                    selected_tool = tool_map.get(tool_name)
                    
                    if selected_tool:
                        speak(f"I am using {tool_name}.")
                        # Debugging output
                        print(f"   > Tool: {tool_name} with args {tool_args}")
                        # Execute
                        tool_output = selected_tool.invoke(tool_args)
                        print(f"   > Tool Output: {tool_output}")
                        
                        self.messages.append(ToolMessage(
                            content=str(tool_output),
                            tool_call_id=tool_call_id,
                            name=tool_name
                        ))
            else:
                print(f"Agent: {ai_msg.content}")
                speak(ai_msg.content)
                break  # Exit the loop