from langchain_ollama import ChatOllama, OllamaEmbeddings
from langchain_chroma import Chroma
from langchain_core.tools import create_retriever_tool
from langchain_core.messages import HumanMessage, SystemMessage, ToolMessage
from tools import get_tools, get_tool_map
from utils import speak
from memory import memory

class EchoAgent:
    def __init__(self):
        # 1. Initialize LLM
        self.llm = ChatOllama(
            model="qwen2.5:1.5b-instruct",
            temperature=0,
        )

        # 2. Load Existing Tools
        self.tools = get_tools()

        # 5. Bind tools to model
        self.llm_with_tools = self.llm.bind_tools(self.tools)
        
        # 6. Update Tool Map (Crucial for execution loop)
        # We need to manually add the new tool to the map so the loop can find it
        self.tool_map = get_tool_map()

        # Load system message from file
        with open("system_prompt.txt", "r") as f:
            starting_system_message = f.read()
            print(f"\nSystem Message:\n{starting_system_message}")
        self.messages = [SystemMessage(content=starting_system_message)]

    async def run(self, user_query, page_content=None, url=None, callback=None):
        print(f"\nUser: {user_query}\nPage Content: {page_content}\nURL: {url}")
        
        memory.set_page_info(page_content, url)
        self.messages.append(HumanMessage(content=user_query))
        
        max_iterations = 5
        iteration = 0
        while iteration < max_iterations:
            iteration += 1
            
            # Invoke Model
            ai_msg = self.llm_with_tools.invoke(self.messages)
            self.messages.append(ai_msg)

            print(self.messages)

            if ai_msg.tool_calls:
                print(f"Agent (Step {iteration}): Thinking... (Calling Tools)")
                
                for tool_call in ai_msg.tool_calls:
                    tool_name = tool_call["name"].lower()
                    tool_args = tool_call["args"]
                    tool_call_id = tool_call["id"]

                    # USE LOCAL TOOL MAP (Updated in __init__)
                    selected_tool = self.tool_map.get(tool_name)
                    
                    if selected_tool:
                        if callback:
                            await callback(f"Loading {tool_name}...")
                        
                        print(f"   > Tool: {tool_name} with args {tool_args}")
                        
                        # Execute Tool
                        try:
                            tool_output = selected_tool.invoke(tool_args)
                        except Exception as e:
                            tool_output = f"Error executing tool: {e}"

                        print(f"   > Output: {str(tool_output)[:100]}...") # Print preview
                        
                        self.messages.append(ToolMessage(
                            content=str(tool_output),
                            tool_call_id=tool_call_id,
                            name=tool_name
                        ))
                    else:
                        print(f"   > Error: Tool {tool_name} not found.")
            else:
                print(f"Output: {ai_msg.content}")
                return ai_msg.content