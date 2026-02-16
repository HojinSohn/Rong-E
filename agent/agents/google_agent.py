



import os
from pathlib import Path
from langchain_google_genai import ChatGoogleGenerativeAI
from agent.services.google_service import AuthManager
from langchain_core.messages import HumanMessage, SystemMessage, ToolMessage
from agent.settings.settings import PROMPTS_DIR

# Google Agent Class
# Simplified agent focused on Google API interactions
class GoogleAgent:
    def __init__(self, auth_manager: AuthManager = None):
        # 1. LLM is set later via set_llm() — no API key required at startup
        self.llm = None
        self.llm_with_tools = None

        # Use shared auth_manager if provided, otherwise create new one
        self.auth_manager = auth_manager if auth_manager else AuthManager()

        self.connected = False

        self.tools = []  
        self.tool_map = {}     
        
        # Load System Prompt
        with open(os.path.join(PROMPTS_DIR, "google_agent_prompt.txt"), "r") as f:
            self.system_prompt = f.read()
        
        self.messages = [SystemMessage(content=self.system_prompt)]
        self.max_iterations = 10

    def set_llm(self, llm):
        """Set the LLM instance for this agent."""
        self.llm = llm
        print("🤖 GoogleAgent LLM updated.")

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
            raise e

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
        if self.llm is not None:
            self.llm_with_tools = self.llm.bind_tools(self.tools)
        else:
            self.llm_with_tools = None

    def reset_tools(self):
        """Reset tools to default state"""
        self.tools = []
        self.tool_map = {}
        self.llm_with_tools = None

    async def run(self, task_description: str) -> str:
        """Runs the agent with the given task description. Task description is provided by the RongEAgent to perform Google-related tasks."""
        
        if self.llm is None:
            return "❌ No LLM configured. Please set an LLM provider before using Google tasks."

        if not self.connected:
            return "❌ Not authenticated with Google APIs."
        
        print("GoogleAgent: Starting task execution...")
        print(f"Task Description: {task_description}")

        final_response = ''

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
            try:
                ai_msg = self.llm_with_tools.invoke(self.messages)
            except Exception as e:
                print(f"GoogleAgent: LLM invocation error: {e}")
                return f"Error: {e}"
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
                        final_response += f"Tool {tool_name} output: {str(tool_output)}\n"
                    else:
                        print(f"   > Error: Tool {tool_name} not found.")
                        self.messages.append(ToolMessage(
                            content=f"Error: Tool {tool_name} not found.",
                            tool_call_id=tool_call_id,
                            name=tool_name
                        ))
                        final_response += f"Tool {tool_name} not found.\n"
            else:
                # Final Response - no more tool calls
                content = ai_msg.content
                if isinstance(content, list):
                    content = "\n".join(
                        block.get("text", "") if isinstance(block, dict) else str(block)
                        for block in content
                    )
                final_response += content
                break
        
        print("GoogleAgent: Task execution completed.")
        print(f"Messages {self.messages}")
        
        # Reset messages for next run
        self.messages = [SystemMessage(content=self.system_prompt)]

        if final_response is not None:
            return final_response

        return "❌ Max iterations reached without a final response."