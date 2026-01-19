import os
import json
import asyncio
from contextlib import AsyncExitStack
from pathlib import Path
import shutil
from dotenv import load_dotenv
from langchain_core.messages import HumanMessage, SystemMessage, ToolMessage
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain.tools import tool

# Agent imports
from agent.agent.google_agent import GoogleAgent
from agent.tools import get_tools
from agent.services.google_service import AuthManager

# --- OFFICIAL MCP IMPORTS ---
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from langchain_mcp_adapters.tools import load_mcp_tools

BASE_DIR = Path(__file__).resolve().parent.parent
PROMPTS_DIR = BASE_DIR / "prompts"

load_dotenv()
from typing import List, Literal, Optional
from pydantic import BaseModel, Field

# 1. Define the Action Schema (The "payload" of the widget)
class WidgetAction(BaseModel):
    url: Optional[str] = Field(None, description="Valid HTTPS URL for links or search results")
    app_name: Optional[str] = Field(None, description="Name of the application to open (e.g., 'Spotify', 'VS Code')")
    code: Optional[str] = Field(None, description="The code snippet to copy or run")
    language: Optional[str] = Field(None, description="Programming language for the code snippet")
    file_path: Optional[str] = Field(None, description="Absolute path to the file to preview")

# 2. Define the Widget Schema
class Widget(BaseModel):
    type: Literal["link", "app_launch", "code_block", "file_preview"] = Field(
        ..., description="The functional type of the widget"
    )
    label: str = Field(..., description="Short, button-like text (2-4 words)")
    icon: str = Field(..., description="SF Symbol name (e.g., 'safari', 'envelope')")
    action: WidgetAction = Field(..., description="The data required to execute the widget's function")

# 3. Define the Container (The LLM will return this object)
class WidgetResponse(BaseModel):
    widgets: List[Widget] = Field(
        default_factory=list, 
        description="A list of 0 to 4 interactive widgets based on the conversation."
    )
class EchoAgent:
    def __init__(self):
        # 1. Initialize Components
        self.llm = ChatGoogleGenerativeAI(
            model="gemini-2.5-flash-lite",
            temperature=0
        )

        self.google_agent = GoogleAgent()
        self.auth_manager = AuthManager()
        
        # 2. Define the Google Tool (Closure with access to self)
        @tool
        async def google_task_executor(task_description: str) -> str:
            """
            Execute Google API tasks like reading emails, managing calendar, or checking drive files.
            Pass the full natural language requirement.
            """
            if not self.google_agent.is_authenticated():
                return "❌ Google APIs not authenticated. Please ask the user to authenticate first."
            
            return await self.google_agent.run(task_description)

        # 3. Load Base Tools and Append Google Tool
        self.base_tools = get_tools() 
        self.base_tools.append(google_task_executor)

        # --- SMART SESSION STATE ---
        self.active_mcp_servers = {} 
        self.tools = []               
        self.tool_map = {}             
        
        self.refresh_active_tools()
        
        with open(os.path.join(PROMPTS_DIR, "system_prompt.txt"), "r") as f:
            self.system_prompt = f.read()

        self.messages = [SystemMessage(content=self.system_prompt)]
        self.max_iterations = 15

    async def authenticate_google(self, token_file: str = None, client_secrets_file: str = None):
        """Authenticate GoogleAgent"""
        await self.google_agent.authenticate(token_file, client_secrets_file)

    def refresh_active_tools(self):
        """Aggregates Base Tools + Tools from all Active MCP Servers"""
        # 1. Start with Base Tools
        all_tools = self.base_tools.copy()

        # 2. Add tools from every active MCP server
        for server_name, server_data in self.active_mcp_servers.items():
            all_tools.extend(server_data["tools"])

        self.tools = all_tools
        
        # 3. Rebuild Map & Bind
        self.tool_map = {}
        for t in self.tools:
            # Handle LangChain StructuredTool names safely
            t_name = t.name if hasattr(t, 'name') else str(t)
            self.tool_map[t_name.lower()] = t
        
        self.llm_with_tools = self.llm.bind_tools(self.tools)
        # print(f"🔄 State Synced: {len(self.tools)} tools active.")

    async def sync_mcp_servers(self, config: dict):
        """
        The Diffing Engine:
        Compares incoming config vs active servers.
        """
        requested_servers = config.get("mcpServers", {})
        current_server_names = set(self.active_mcp_servers.keys())
        requested_server_names = set(requested_servers.keys())

        # 1. Calculate Diff
        to_add = requested_server_names - current_server_names
        to_remove = current_server_names - requested_server_names
        
        # 2. Handle Removals
        for name in to_remove:
            print(f"🔻 Stopping MCP Server: {name}")
            server_data = self.active_mcp_servers.pop(name)
            await server_data["stack"].aclose()

        # 3. Handle Additions
        for name in to_add:
            print(f"🔺 Starting MCP Server: {name}")
            server_config = requested_servers[name]
            await self._start_single_server(name, server_config)

        # 4. Refresh Tools if state changed
        if to_add or to_remove:
            self.refresh_active_tools()
        else:
            print("✅ MCP Config unchanged. Keeping connections alive.")

    async def _start_single_server(self, name: str, config: dict):
        """Helper to start a single server and store its state"""
        try:
            stack = AsyncExitStack()
            
            command = config.get("command")
            args = config.get("args", [])
            env = config.get("env", {})
            
            full_env = os.environ.copy()
            full_env.update(env)
            executable = shutil.which(command) or command

            server_params = StdioServerParameters(command=executable, args=args, env=full_env)

            # Enter context
            stdio_transport = await stack.enter_async_context(stdio_client(server_params))
            read, write = stdio_transport
            session = await stack.enter_async_context(ClientSession(read, write))
            
            await session.initialize()
            
            # Load Tools
            mcp_tools = await load_mcp_tools(session)
            
            # STORE IN STATE
            self.active_mcp_servers[name] = {
                "session": session,
                "stack": stack,
                "tools": mcp_tools
            }
            
        except Exception as e:
            print(f"❌ Failed to start {name}: {e}")
            await stack.aclose()

    async def shutdown_all_servers(self):
        """Full cleanup"""
        keys = list(self.active_mcp_servers.keys())
        for name in keys:
            server_data = self.active_mcp_servers.pop(name)
            await server_data["stack"].aclose()
        self.refresh_active_tools()
        print("🛑 All MCP Servers shut down.")

    async def run(self, user_query, mode=None, base64_image=None, callback=None):
        return await self._execute_run_loop(user_query, base64_image, callback)

    async def _generate_widgets_with_llm(self, user_query: str, response_text: str, tool_history: list) -> list:
        """
        Generates widgets using Structured Output.
        Returns a clean list of dictionaries, guaranteed to match the schema.
        """
        # --- 1. Prepare Context (Same as before) ---
        safe_text = (response_text[:2000] + '...') if len(response_text) > 2000 else response_text
        
        tool_summary_lines = []
        if tool_history:
            for t in tool_history[-5:]:
                args_str = str(t.get('args', {}))[:200]
                out_str = str(t.get('output', ''))[:200]
                tool_summary_lines.append(f"- Tool: {t.get('name')}\n  Args: {args_str}\n  Output: {out_str}")
        
        context_str = "\n".join(tool_summary_lines) if tool_summary_lines else "No tools used."

        # --- 2. Configure the Structured LLM ---
        # We use a low temperature for strict adherence to facts/links
        structured_llm = self.llm.with_structured_output(WidgetResponse)

        prompt = f"""
        Analyze the conversation and generate interactive widgets.
        
        USER QUERY: {user_query}
        AI RESPONSE: {safe_text}
        TOOL HISTORY: {context_str}
        
        Rules:
        1. If a URL is mentioned, create a 'link' widget.
        2. If the user asks to open an app, create an 'app_launch' widget.
        3. If a file was created or read, create a 'file_preview' widget.
        4. Do not hallucinate URLs. Use only what is present in the context.
        """

        try:
            # --- 3. Execute (Returns a Pydantic Object, not string!) ---
            result: WidgetResponse = await structured_llm.ainvoke(prompt)
            
            # --- 4. Convert back to Dict for your frontend ---
            # The result is already validated. We just need to dump it.
            valid_widgets = [w.dict() for w in result.widgets]
            
            # Optional: Extra sanity check on URLs (Pydantic validates structure, not 404s)
            final_widgets = []
            for w in valid_widgets:
                if w['type'] == 'link' and (not w['action'].get('url') or 'http' not in w['action']['url']):
                    continue
                final_widgets.append(w)

            return final_widgets

        except Exception as e:
            print(f"❌ Structured Output Failed: {e}")
            return []

    async def _execute_run_loop(self, user_query, base64_image, callback):
        print(f"\nUser: {user_query}")

        if base64_image:
            image_url = base64_image if base64_image.startswith("data:") else f"data:image/jpeg;base64,{base64_image}"
            message_content = [{"type": "text", "text": user_query}, {"type": "image_url", "image_url": {"url": image_url}}]
        else:
            message_content = user_query

        self.messages.append(HumanMessage(content=message_content))
        iteration = 0
        tool_history = []  # Track tool calls for widget generation

        try:
            while iteration < self.max_iterations:
                iteration += 1
                ai_msg = await self.llm_with_tools.ainvoke(self.messages)
                self.messages.append(ai_msg)

                if ai_msg.tool_calls:
                    if callback: await callback("thought", ai_msg.content)

                    for tool_call in ai_msg.tool_calls:
                        tool_name = tool_call["name"].lower()
                        tool_args = tool_call["args"]
                        tool_call_id = tool_call["id"]

                        if callback: await callback("tool_call", {"toolName": tool_name, "toolArgs": tool_args})

                        selected_tool = self.tool_map.get(tool_name)
                        if selected_tool:
                            print(f"   > Tool: {tool_name}")
                            try:
                                if hasattr(selected_tool, "ainvoke"):
                                    tool_output = await selected_tool.ainvoke(tool_args)
                                else:
                                    tool_output = selected_tool.invoke(tool_args)
                            except Exception as e:
                                tool_output = f"Error: {e}"

                            # Track tool usage for widget generation
                            tool_history.append({
                                "name": tool_name,
                                "args": tool_args,
                                "output": str(tool_output)[:1000]  # Limit output size
                            })

                            self.messages.append(ToolMessage(content=str(tool_output), tool_call_id=tool_call_id, name=tool_name))
                            if callback: await callback("tool_result", {"toolName": tool_name, "result": str(tool_output)})
                        else:
                            self.messages.append(ToolMessage(content=f"Error: Tool {tool_name} not found", tool_call_id=tool_call_id, name=tool_name))
                else:
                    # Generate widgets using LLM
                    widgets = await self._generate_widgets_with_llm(
                        user_query,
                        ai_msg.content,
                        tool_history
                    )

                    response_data = {
                        "text": ai_msg.content,
                        "images": [],
                        "widgets": widgets
                    }

                    if callback: await callback("response", response_data)
                    return response_data

        except Exception as e:
            print(f"Error: {e}")
            return {"text": str(e), "images": [], "widgets": []}