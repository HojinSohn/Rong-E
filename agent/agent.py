import os
import re
import json
from pathlib import Path
from dotenv import load_dotenv

from langchain_core.messages import HumanMessage, SystemMessage, ToolMessage
from langchain_google_genai import ChatGoogleGenerativeAI

# Agent imports
from agent.tools import get_tools, get_tool_map
from agent.settings.settings import PROMPTS_DIR
from agent.services.media import fetch_images
from agent.services.google_service import AuthManager
from agent.models.model import ThoughtContentSchema, ToolCallSchema, ToolResultSchema, ResponseContentSchema

BASE_DIR = Path(__file__).resolve().parent
PROMPTS_DIR = BASE_DIR / "prompts"

load_dotenv()

class EchoAgent:
    def __init__(self):
        # 1. Initialize LLM
        self.llm = ChatGoogleGenerativeAI(
            model="gemini-2.5-flash-lite",
            temperature=0
        )

        # 2. Initialize Google Auth Manager
        self.auth_manager = AuthManager()

        # 3. Load Existing Tools
        self.tools = get_tools()

        # 4. Bind tools to model
        self.bind_tools()
        
        # Load System Prompt
        with open(os.path.join(PROMPTS_DIR, "system_prompt.txt"), "r") as f:
            self.system_prompt = f.read()

        self.messages = [SystemMessage(content=self.system_prompt)]
        self.tool_map = get_tool_map()

        self.max_iterations = 15

    def bind_tools(self):
        self.llm_with_tools = self.llm.bind_tools(self.tools)

    def add_tools(self, new_tools):
        self.tools.extend(new_tools)
        self.tool_map = get_tool_map()
        for tool in new_tools:
            self.tool_map[tool.name.lower()] = tool
        self.bind_tools()

    def reset_tools(self):
        self.tools = get_tools()
        self.tool_map = get_tool_map()
        self.bind_tools()

    async def authenticate_google(self, token_file: str = None, client_secrets_file: str = None):
        if self.auth_manager.check_connected():
            print("Already authenticated with Google APIs.")
            return
        
        await self.auth_manager.authenticate(
            token_file=token_file,
            client_secrets_file=client_secrets_file
        )
        
        google_tools = self.auth_manager.get_google_tools()
        self.add_tools(google_tools)

    def revoke_google_credentials(self):
        if not self.auth_manager.check_connected():
            print("No Google credentials to revoke.")
            return
        self.auth_manager.credentials = None
        self.reset_tools()

    async def run(self, user_query, mode=None, base64_image=None, callback=None):
        print(f"\nUser: {user_query}")

        # Construct message content
        if base64_image:
            image_url = base64_image if base64_image.startswith("data:") else f"data:image/jpeg;base64,{base64_image}"
            message_content = [
                {"type": "text", "text": user_query},
                {"type": "image_url", "image_url": image_url}
            ]
        else:
            message_content = user_query

        self.messages.append(HumanMessage(content=message_content))
        
        iteration = 0

        print("---- Current Conversation ----")
        print(self.messages)
        print("------------------------------")
        while iteration < self.max_iterations:
            iteration += 1
            
            # Invoke Model
            ai_msg = self.llm_with_tools.invoke(self.messages)
            self.messages.append(ai_msg)
            
            print(ai_msg)

            if ai_msg.tool_calls:
                print(f"Agent (Step {iteration}): Thinking... (Calling Tools)")
                if ai_msg.content:
                    print(f"   > Thought: {ai_msg.content}")
                    self.messages.append(ai_msg)

                    # Send thought to callback if provided
                    if callback:

                        await callback("thought", ThoughtContentSchema(text=ai_msg.content).model_dump())    

                for tool_call in ai_msg.tool_calls:
                    tool_name = tool_call["name"].lower()
                    tool_args = tool_call["args"]
                    tool_call_id = tool_call["id"]

                    if callback:
                       payload = ToolCallSchema(toolName=tool_name, toolArgs=tool_args).model_dump()
                       await callback("tool_call", payload)

                    selected_tool = self.tool_map.get(tool_name)
                    
                    if selected_tool:
                        print(f"   > Tool: {tool_name} with args {tool_args}")
                        
                        try:
                            tool_output = selected_tool.invoke(tool_args)
                        except Exception as e:
                            tool_output = f"Error executing tool: {e}"

                        print(f"   > Output: {str(tool_output)[:100]}...")
                        
                        self.messages.append(ToolMessage(
                            content=str(tool_output),
                            tool_call_id=tool_call_id,
                            name=tool_name
                        ))

                        if callback:
                           result_payload = ToolResultSchema(toolName=tool_name, result=str(tool_output)).model_dump()
                           await callback("tool_result", result_payload)
                    else:
                        print(f"   > Error: Tool {tool_name} not found.")
                        self.messages.append(ToolMessage(
                            content=f"Error: Tool {tool_name} not found.",
                            tool_call_id=tool_call_id,
                            name=tool_name
                        ))
                        if callback:
                            error_payload = ToolResultSchema(toolName=tool_name, result=f"Error: Tool {tool_name} not found.").model_dump()
                            await callback("tool_result", error_payload)
            else:
                # Final Response Logic
                print(f"Output: {ai_msg.content}")
                
                # 1. Parse content for Image Tags based on System Prompt Instructions
                images = []

                _response_content = ResponseContentSchema(text=ai_msg.content, images=images).model_dump()
                if callback:
                    await callback("response", _response_content)
                return _response_content
        
        _error_content = ResponseContentSchema(
            text="❌ Max iterations reached without a final response.",
            images=[]
        ).model_dump()

        if callback:
            await callback("response", _error_content)
        
        return _error_content