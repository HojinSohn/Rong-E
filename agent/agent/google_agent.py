



import os
from pathlib import Path
from langchain_google_genai import ChatGoogleGenerativeAI
from agent.services.google_service import AuthManager
from langchain_core.messages import HumanMessage, SystemMessage, ToolMessage
from agent.settings.settings import PROMPTS_DIR

# Google Agent Class
# Simplified agent focused on Google API interactions
# Should not share state with EchoAgent. Independent Agent for Google tasks.
class GoogleAgent:
    def __init__(self):
        # 1. Initialize LLM
        self.llm = ChatGoogleGenerativeAI(
            model="gemini-2.5-flash-lite",
            temperature=0
        )

        self.llm_with_tools = None

        self.auth_manager = AuthManager()

        self.connected = False

        self.tools = []  
        self.tool_map = {}     
        
        # Load System Prompt
        with open(os.path.join(PROMPTS_DIR, "google_agent_prompt.txt"), "r") as f:
            self.system_prompt = f.read()
        
        self.messages = [SystemMessage(content=self.system_prompt)]
        self.max_iterations = 10

    def is_authenticated(self) -> bool:
        """Check if authenticated with Google APIs"""
        return self.auth_manager.check_connected()

    async def authenticate(self, token_file: str = None, client_secrets_file: str = None):
        """Handles Google Authentication Flow"""
        if self.auth_manager.check_connected():
            self.connected = True
            print("Already authenticated with Google APIs.")
            return
        
        try:
            await self.auth_manager.authenticate(
                token_file=token_file,
                client_secrets_file=client_secrets_file
            )
            self.connected = True
            print("Successfully authenticated with Google APIs.")
        except Exception as e:
            self.connected = False
            print(f"Authentication failed: {e}")

    async def refresh_credentials(self):
        """Refreshes Google API Credentials"""
        await self.auth_manager.authenticate()

    async def revoke_credentials(self):
        """Revokes Google API Credentials"""
        if not self.auth_manager.check_connected():
            print("No Google credentials to revoke.")
            return
        self.auth_manager.credentials = None
        self.reset_tools()

    def bind_tools(self):
        self.tools = []
        self.tool_map = {}
        google_tools = self.auth_manager.get_google_tools()
        for tool in google_tools:
            self.tools.append(tool)
            self.tool_map[tool.name.lower()] = tool
        self.llm_with_tools = self.llm.bind_tools(self.tools)

    def reset_tools(self):
        """Reset tools to default state"""
        self.tools = []
        self.tool_map = {}
        self.llm_with_tools = None

    async def run(self, task_description: str) -> str:
        """Runs the agent with the given task description. Task description is provided by the EchoAgent to perform Google-related tasks."""
        
        if not self.connected:
            return "❌ Not authenticated with Google APIs."
        
        print("GoogleAgent: Starting task execution...")
        print(f"Task Description: {task_description}")

        final_response = None

        # 1. Reset message history and append new task
        self.messages = [SystemMessage(content=self.system_prompt)]
        self.messages.append(HumanMessage(content=task_description))

        # 2. Bind Tools
        self.bind_tools()

        # 3. Agentic Loop
        iteration = 0
        while iteration < self.max_iterations:
            iteration += 1
            
            # Invoke LLM with Tools
            ai_msg = self.llm_with_tools.invoke(self.messages)
            self.messages.append(ai_msg)
            
            # Check if we have tool calls
            if ai_msg.tool_calls:
                print(f"GoogleAgent (Step {iteration}): Calling {len(ai_msg.tool_calls)} tool(s)")
                if ai_msg.content:
                    print(f"   > Thought: {ai_msg.content}")
                    
                for tool_call in ai_msg.tool_calls:
                    tool_name = tool_call["name"].lower()
                    tool_args = tool_call["args"]
                    tool_call_id = tool_call["id"]
                    
                    selected_tool = self.tool_map.get(tool_name)
                    
                    if selected_tool:
                        print(f"   > Tool: {tool_name}")
                        try:
                            tool_output = selected_tool.invoke(tool_args)
                        except Exception as e:
                            tool_output = f"Error executing tool: {e}"
                        
                        self.messages.append(ToolMessage(
                            content=str(tool_output),
                            tool_call_id=tool_call_id,
                            name=tool_name
                        ))
                    else:
                        print(f"   > Error: Tool {tool_name} not found.")
                        self.messages.append(ToolMessage(
                            content=f"Error: Tool {tool_name} not found.",
                            tool_call_id=tool_call_id,
                            name=tool_name
                        ))
            else:
                # Final Response - no more tool calls
                final_response = ai_msg.content
                break
        
        print("GoogleAgent: Task execution completed.")
        print(f"Messages {self.messages}")
        
        # Reset messages for next run
        self.messages = [SystemMessage(content=self.system_prompt)]

        if final_response is not None:
            return final_response

        return "❌ Max iterations reached without a final response."