import os
from langchain_ollama import ChatOllama, OllamaEmbeddings
from langchain_anthropic import ChatAnthropic
from langchain_chroma import Chroma
from langchain_core.messages import HumanMessage, SystemMessage, ToolMessage
from agent.tools import get_tools, get_tool_map
from agent.settings.settings import PROMPTS_DIR
from agent.services.media import fetch_images
from langchain_google_genai import ChatGoogleGenerativeAI
from dotenv import load_dotenv
import google.genai as genai
from agent.services.google_service import AuthManager


from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent

PROMPTS_DIR = BASE_DIR / "prompts"

load_dotenv()
class EchoAgent:
    def __init__(self):
        # # 1. Initialize LLM
        self.llm = ChatGoogleGenerativeAI(
            model="gemini-2.5-flash-lite",
            temperature=0
        )

        self.plan_llm = ChatGoogleGenerativeAI(
            model="gemini-2.5-flash-lite",
            temperature=0
        )
        self.image_llm = ChatGoogleGenerativeAI(
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
        with open(os.path.join(PROMPTS_DIR, "system_prompt.txt"), "r") as f: # Updated path
            self.system_prompt = f.read()

        self.messages = [SystemMessage(content=self.system_prompt)]
        self.tool_map = get_tool_map()

    def bind_tools(self):
        self.llm_with_tools = self.llm.bind_tools(self.tools)
        self.plan_llm_with_tools = self.plan_llm.bind_tools(self.tools)

    def add_tools(self, new_tools):
        self.tools.extend(new_tools)
        self.tool_map = get_tool_map()
        # Update tool map with new tools
        for tool in new_tools:
            self.tool_map[tool.name.lower()] = tool
        
        # Re-bind tools to model
        self.bind_tools()

    def reset_tools(self):
        self.tools = get_tools()  # Reload base tools
        self.tool_map = get_tool_map()
        # Re-bind tools to model
        self.bind_tools()

    async def authenticate_google(self, token_file: str = None, client_secrets_file: str = None):
        if self.auth_manager.check_connected():
            print("Already authenticated with Google APIs.")
            return
        
        await self.auth_manager.authenticate(
            token_file=token_file,
            client_secrets_file=client_secrets_file
        )
        
        # Refresh tools with authenticated Google tools
        google_tools = self.auth_manager.get_google_tools()
        # Add Google tools to agent
        self.add_tools(google_tools)

    def revoke_google_credentials(self):
        if not self.auth_manager.check_connected():
            print("No Google credentials to revoke.")
            return
        
        # Clear credentials
        self.auth_manager.credentials = None
        
        # Refresh tools without Google tools
        self.reset_tools()

    def get_images(self, user_query, agent_response, count=3):
        image_prompt = None

        with open(os.path.join(PROMPTS_DIR, "image_prompt.txt"), "r") as f:
            image_prompt = f.read()

        image_msg = self.image_llm.invoke([
            SystemMessage(content=image_prompt),
            HumanMessage(content=f"Generate an image search query based on the following information:\n\nUser Query: {user_query}\n\nAgent Response: {agent_response}")
        ])

        print(f"Image Query: {image_msg.content}")

        images = fetch_images(image_msg.content, count=count)

        return images

    def get_plan(self, user_query, mode):
        plan_prompt = None
        plan_msg = None

        if mode == "mode1":
            # Default mode
            plan_prompt = None
        elif mode == "mode2":
            # Plan out the logical processing steps
            with open(os.path.join(PROMPTS_DIR, "plan_prompt.txt"), "r") as f:
                plan_prompt = f.read()
        else:
            # Custom mode, open file and read prompt
            with open(os.path.join(PROMPTS_DIR, f"mode_{mode}_prompt.txt"), "r") as f:
                plan_prompt = f.read()

        if plan_prompt:
            plan_msg = self.plan_llm_with_tools.invoke([SystemMessage(content=plan_prompt), HumanMessage(content=user_query)])
            print(f"Plan: {plan_msg.content}")

        return plan_msg

    async def run(self, user_query, mode, base64_image=None, callback=None):
        print(f"\nUser: {user_query}")


        if base64_image:
            if not base64_image.startswith("data:"):
                image_url = f"data:image/jpeg;base64,{base64_image}"
            else:
                image_url = base64_image
            message_content = [
                {
                    "type": "text",
                    "text": user_query
                },
                {
                    "type": "image_url",
                    "image_url": image_url  # Standard LangChain format
                }
            ]
        else:
            message_content = user_query

        self.messages.append(HumanMessage(content=message_content))
        
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

                print(f"Agent message: {ai_msg}")
                
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

                        print(f"   > Output: {str(tool_output)}...") # Print preview
                        
                        self.messages.append(ToolMessage(
                            content=str(tool_output),
                            tool_call_id=tool_call_id,
                            name=tool_name
                        ))
                    else:
                        print(f"   > Error: Tool {tool_name} not found.")
            else:
                print(f"Output: {ai_msg.content}")

                images = []

                # # Fetch images
                # images = self.get_images(user_query, ai_msg.content)
                
                # # Structure the response as JSON
                # response = {
                #     "text": ai_msg.content,
                #     "images": images if images else []
                # }
                
                # print(f"Images: {json.dumps(images, indent=2)}")
                
                # For final response with images
                response = {
                    "type": "final",
                    "content": {
                        "text": ai_msg.content,
                        "images": images if images else []
                    }
                }
                
                return response