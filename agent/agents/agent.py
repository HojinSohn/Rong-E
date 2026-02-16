import os
import glob
import asyncio
from contextlib import AsyncExitStack
from pathlib import Path
import shutil
from sys import executable
from dotenv import load_dotenv
from langchain_core.messages import HumanMessage, SystemMessage, ToolMessage
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_openai import ChatOpenAI
from langchain_ollama import ChatOllama
from langchain_anthropic import ChatAnthropic
from langchain.tools import tool
from datetime import datetime

# Agent imports
from agent.agents.google_agent import GoogleAgent
from agent.tools import get_tools, get_memory_content
from agent.services.google_service import AuthManager
from agent.settings.settings import PROMPTS_DIR

# --- OFFICIAL MCP IMPORTS ---
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from langchain_mcp_adapters.tools import load_mcp_tools

from typing import List, Literal, Optional
from pydantic import BaseModel, Field

load_dotenv()

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
def _extract_text(content) -> str:
    """Normalize ai_msg.content to a plain string.
    Gemini/OpenAI return str, Anthropic returns list of content blocks."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text", ""))
            elif isinstance(block, str):
                parts.append(block)
        return "\n".join(parts)
    return str(content)

class RongEAgent:
    def __init__(self):
        # 1. Initialize Components
        self.current_provider = None
        self.current_model = None
        self.llm = None
        self.llm_with_tools = None

        # Single shared auth_manager for the entire session
        self.auth_manager = AuthManager()
        self.google_agent = GoogleAgent(auth_manager=self.auth_manager)
        
        # 2. Define the Google Tool (Closure with access to self)
        @tool
        async def google_task_executor(task_description: str) -> str:
            """
            Execute Google API tasks like reading emails, managing calendar, or checking drive files.
            Pass the full natural language requirement.
            """
            if not self.google_agent.is_authenticated():
                return "❌ Google APIs not authenticated. Please ask the user to authenticate first."

            current_date_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

            # Include spreadsheet context if available
            spreadsheet_context = self.auth_manager.get_spreadsheet_context()

            context_parts = [task_description, f"Current date and time: {current_date_time}."]
            if spreadsheet_context:
                context_parts.append(spreadsheet_context)

            full_task_description = "\n\n".join(context_parts)

            return await self.google_agent.run(full_task_description)

        # 3. Load Base Tools and Append Google Tool
        self.base_tools = get_tools() 
        self.base_tools.append(google_task_executor)

        # --- SMART SESSION STATE ---
        self.active_mcp_servers = {} 
        self.tools = []               
        self.tool_map = {}             
        
        self.refresh_active_tools()
        
        # --- SYSTEM PROMPT & MESSAGES ---
        self.create_system_prompt()

        self.messages = [SystemMessage(content=self.system_prompt)]
        self.max_iterations = 15

    def create_system_prompt(self, mode_system_prompt=None, user_name=None):
        """Create a custom system prompt with additional instructions."""
        with open(os.path.join(PROMPTS_DIR, "system_prompt.txt"), "r") as f:
            base_prompt = f.read()

        # Substitute user name placeholder
        if user_name:
            base_prompt = base_prompt.replace("{user_name}", user_name)
        else:
            base_prompt = base_prompt.replace("{user_name}", "User")

        custom_instructions = f'Current date and time: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}.'

        # Include mode-specific system prompt from the UI
        if mode_system_prompt:
            custom_instructions += f'\n\nAdditional mode instructions: {mode_system_prompt}'

        # Include spreadsheet context if available
        spreadsheet_context = self.auth_manager.get_spreadsheet_context()

        # Include persistent memory if available
        memory_content = get_memory_content()
        memory_section = ""
        if memory_content:
            memory_section = f"""### Persistent Memory
The following is your persistent memory containing important information about the user:

{memory_content}

Use this information to provide personalized assistance. Update memory when you learn important new facts about the user."""

        parts = [base_prompt, custom_instructions]
        if spreadsheet_context:
            parts.append(spreadsheet_context)
        if memory_section:
            parts.append(memory_section)

        self.system_prompt = "\n\n".join(parts)

    def update_system_prompt(self, mode_system_prompt=None, user_name=None):
        """Update the system prompt and refresh the first message."""
        self.create_system_prompt(mode_system_prompt=mode_system_prompt, user_name=user_name)
        if self.messages:
            self.messages[0] = SystemMessage(content=self.system_prompt)

    def set_llm(self, provider: str, model: str, api_key: str = None):
        """Switch the LLM provider and model at runtime. Validates by sending a test message."""
        if provider == "gemini":
            kwargs = {"model": model, "temperature": 0}
            if api_key:
                kwargs["google_api_key"] = api_key
            new_llm = ChatGoogleGenerativeAI(**kwargs)
        elif provider == "openai":
            kwargs = {"model": model, "temperature": 0}
            if api_key:
                kwargs["api_key"] = api_key
            new_llm = ChatOpenAI(**kwargs)
        elif provider == "ollama":
            new_llm = ChatOllama(model=model, temperature=0)
        elif provider == "anthropic":
            kwargs = {"model": model, "temperature": 0}
            if api_key:
                kwargs["api_key"] = api_key
            new_llm = ChatAnthropic(**kwargs)
        else:
            raise ValueError(f"Unknown LLM provider: {provider}")

        # Validate by sending a test message
        try:
            new_llm.invoke("Say OK")
        except Exception as e:
            raise ValueError(f"Validation failed for {provider}/{model}: {e}")

        # Apply the validated LLM
        self.llm = new_llm
        self.current_provider = provider
        self.current_model = model

        # Propagate LLM to sub-agents
        self.google_agent.set_llm(new_llm)

        # Rebind tools with the new LLM
        self.refresh_active_tools()
        print(f"🤖 LLM switched to {provider} / {model}")

    async def authenticate_google(self, token_file: str = None, client_secrets_file: str = None):
        """Authenticate GoogleAgent"""
        await self.google_agent.authenticate(token_file, client_secrets_file)

    async def revoke_google_credentials(self):
        """Revoke Google Credentials"""
        await self.google_agent.revoke_credentials()

    def reset_session(self):
        """Reset conversation history to just the system prompt."""
        self.messages = [SystemMessage(content=self.system_prompt)]
        print("🔄 Session reset. Conversation history cleared.")

    def get_active_tools_info(self) -> list:
        """Return list of active tools with their source."""
        tools_info = []
        base_tool_names = {t.name for t in self.base_tools}
        for t in self.tools:
            name = t.name if hasattr(t, 'name') else str(t)
            if name in base_tool_names:
                tools_info.append({"name": name, "source": "base"})
            else:
                # Find which MCP server this tool belongs to
                source = "mcp"
                for server_name, server_data in self.active_mcp_servers.items():
                    server_tool_names = {st.name for st in server_data["tools"]}
                    if name in server_tool_names:
                        source = server_name
                        break
                tools_info.append({"name": name, "source": source})
        return tools_info

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

        if self.llm is not None:
            self.llm_with_tools = self.llm.bind_tools(self.tools)
        else:
            self.llm_with_tools = None
        # print(f"🔄 State Synced: {len(self.tools)} tools active.")

    async def sync_mcp_servers(self, config: dict) -> dict:
        """
        The Diffing Engine:
        Compares incoming config vs active servers.
        Returns per-server results: {name: {"status": "connected"|"error", "error": str|None}}
        """
        requested_servers = config.get("mcpServers", {})
        current_server_names = set(self.active_mcp_servers.keys())
        requested_server_names = set(requested_servers.keys())

        # 1. Calculate Diff
        to_add = requested_server_names - current_server_names
        to_remove = current_server_names - requested_server_names

        results = {}

        # 2. Handle Removals (with error protection)
        for name in to_remove:
            print(f"🔻 Stopping MCP Server: {name}")
            server_data = self.active_mcp_servers.pop(name)
            try:
                await asyncio.shield(server_data["stack"].aclose())
            except Exception as e:
                print(f"⚠️ Error closing {name}: {e}")

        # 3. Handle Additions
        for name in to_add:
            print(f"🔺 Starting MCP Server: {name}")
            server_config = requested_servers[name]
            success, error = await self._start_single_server(name, server_config)
            if success:
                results[name] = {"status": "connected", "error": None}
            else:
                results[name] = {"status": "error", "error": error}

        # 4. Include already-running servers as connected
        for name in (requested_server_names & current_server_names):
            results[name] = {"status": "connected", "error": None}

        # 5. Refresh Tools if state changed
        if to_add or to_remove:
            self.refresh_active_tools()
        else:
            print("✅ MCP Config unchanged. Keeping connections alive.")

        return results

    def get_server_statuses(self) -> dict:
        """Returns current active server names with connected status."""
        return {
            name: {"status": "connected", "error": None}
            for name in self.active_mcp_servers
        }

    async def _start_single_server(self, name: str, config: dict) -> tuple[bool, str | None]:
        """Helper to start a single server and store its state. Returns (success, error_msg)."""
        stack = AsyncExitStack()
        success = False
        error_msg = None

        try:
            command = config.get("command")
            args = config.get("args", [])
            env = config.get("env", {})

            full_env = os.environ.copy()
            full_env.update(env)

            # Expand PATH to include common Node.js/npm locations (for macOS app bundles)
            home = os.path.expanduser("~")
            extra_paths = [
                f"{home}/.nvm/versions/node/*/bin",  # nvm
                "/opt/homebrew/bin",                  # Homebrew Apple Silicon
                "/usr/local/bin",                     # Homebrew Intel / standard
                f"{home}/.local/bin",                 # pipx, etc.
                "/opt/local/bin",                     # MacPorts
            ]
            # Resolve glob patterns and filter existing paths
            expanded_paths = []
            for p in extra_paths:
                if '*' in p:
                    expanded_paths.extend(glob.glob(p))
                elif os.path.isdir(p):
                    expanded_paths.append(p)

            if expanded_paths:
                current_path = full_env.get("PATH", "")
                full_env["PATH"] = ":".join(expanded_paths) + ":" + current_path

            executable = shutil.which(command, path=full_env.get("PATH")) or command

            server_params = StdioServerParameters(command=executable, args=args, env=full_env)

            # 2. Enter contexts within the same task
            stdio_transport = await stack.enter_async_context(stdio_client(server_params))
            read, write = stdio_transport
            
            # 3. Use a reasonable timeout for initialization to prevent hanging
            async with asyncio.timeout(10): 
                session = await stack.enter_async_context(ClientSession(read, write))
                await session.initialize()

            mcp_tools = await load_mcp_tools(session)

            self.active_mcp_servers[name] = {
                "session": session,
                "stack": stack,
                "tools": mcp_tools
            }
            success = True

        except (Exception, asyncio.CancelledError) as e:
            print(f"❌ Failed to start {name}: {e}")
            error_msg = str(e)
            # 4. Do NOT call stack.aclose() here. Let the finally block handle it 
            # to ensure the exit stack is unwound in the correct task context.
            success = False
        
        finally:
            if not success:
                # Only clean up if we didn't successfully register the server
                await stack.aclose()

        return (success, error_msg)

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
        if self.llm is None:
            return []

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
        if self.llm is None or self.llm_with_tools is None:
            error_msg = "No LLM configured. Please set an LLM provider before sending commands."
            if callback:
                await callback("response", {"text": error_msg, "images": [], "widgets": []})
            return {"text": error_msg, "images": [], "widgets": []}

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
                    if callback: await callback("thought", _extract_text(ai_msg.content))

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
                    response_text = _extract_text(ai_msg.content)
                    widgets = await self._generate_widgets_with_llm(
                        user_query,
                        response_text,
                        tool_history
                    )

                    response_data = {
                        "text": response_text,
                        "images": [],
                        "widgets": widgets
                    }

                    if callback: await callback("response", response_data)
                    return response_data

        except Exception as e:
            print(f"Error: {e}")
            error_data = {"text": f"Error: {e}", "images": [], "widgets": []}
            if callback:
                await callback("response", error_data)
            return error_data