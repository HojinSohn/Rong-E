import datetime
import os
import platform
from langchain_core.tools import tool
from langchain_community.tools import DuckDuckGoSearchRun
import subprocess
from typing import List
from agent.models.model import (
    JobApplicationSchema,
    WebSearchSchema,
    ListDirectorySchema,
    ReadFileSchema,
    CollectFilesSchema,
    SeparateFilesSchema,
    OpenApplicationSchema
)
from agent.settings.settings import MEMORY_FILE

search = DuckDuckGoSearchRun()

@tool("web_search", description="Useful for searching the internet for current events or facts.", args_schema=WebSearchSchema)
def web_search(query: str):
    """Useful for searching the internet for current events or facts."""
    return search.run(query)

@tool("get_current_date_time", description="Returns the current local date and time.")
def get_current_date_time():
    """Returns the current local date and time."""
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

@tool("pwd", description="Returns the current working directory.")
def pwd():
    """Returns the current working directory."""
    return os.getcwd()

@tool("open_application", description="Opens a specified application on the system.", args_schema=OpenApplicationSchema)
def open_application(app_name: str):
    """Opens a specified application on the system."""
    try: 
        if platform.system() == "Windows":
            os.startfile(app_name)
        elif platform.system() == "Darwin":  # macOS
            os.system(f"open -a '{app_name}'")
            cmd = f'osascript -e \'activate application "{app_name}"\''
            subprocess.run(cmd, shell=True)
            print(f"YEEEEEEE {app_name}")
        elif platform.system() == "Linux":
            os.system(f"xdg-open '{app_name}'")
        else:
            return f"Unsupported operating system: {platform.system()}"
        
    except Exception as e:
        return f"Failed to open {app_name}: {e}"
    return f"Opened {app_name}"

@tool
def open_chrome_tab(url: str):
    """Opens a specific URL in the user's visible Google Chrome browser."""
    apple_script = f'''
    tell application "Google Chrome"
        activate
        if (count every window) = 0 then
            make new window
        end if
        tell window 1
            make new tab with properties {{URL: "{url}"}}
        end tell
    end tell
    '''
    subprocess.run(["osascript", "-e", apple_script])
    return f"Opened {url} in Chrome."


# ============================================================================
# MEMORY TOOLS - Persistent storage for important information
# ============================================================================

@tool
def read_memory() -> str:
    """
    Read the entire contents of the persistent memory file.
    Use this to recall previously stored information about the user, preferences, or important facts.
    """
    try:
        if os.path.exists(MEMORY_FILE):
            with open(MEMORY_FILE, "r", encoding="utf-8") as f:
                content = f.read()
            return content if content.strip() else "Memory is empty."
        return "Memory file does not exist yet. Use save_to_memory to create it."
    except Exception as e:
        return f"Error reading memory: {e}"


@tool
def save_to_memory(content: str) -> str:
    """
    Completely replace the memory file with new content.
    Use this when you need to reorganize or rewrite the entire memory.
    The content should be well-structured markdown.

    Args:
        content: The full markdown content to save to memory
    """
    try:
        with open(MEMORY_FILE, "w", encoding="utf-8") as f:
            f.write(content)
        return f"✅ Memory saved successfully ({len(content)} characters)"
    except Exception as e:
        return f"❌ Error saving memory: {e}"


@tool
def append_to_memory(content: str) -> str:
    """
    Append new information to the end of the memory file.
    Use this to add new facts, preferences, or important information without overwriting existing memory.

    Args:
        content: The markdown content to append (will be added with a newline separator)
    """
    try:
        # Read existing content
        existing = ""
        if os.path.exists(MEMORY_FILE):
            with open(MEMORY_FILE, "r", encoding="utf-8") as f:
                existing = f.read()

        # Append new content with proper separation
        separator = "\n\n" if existing.strip() else ""
        new_content = existing + separator + content

        with open(MEMORY_FILE, "w", encoding="utf-8") as f:
            f.write(new_content)

        return f"✅ Appended to memory successfully"
    except Exception as e:
        return f"❌ Error appending to memory: {e}"


def get_memory_content() -> str:
    """
    Helper function to load memory content for system prompt injection.
    Returns empty string if no memory exists.
    """
    try:
        if os.path.exists(MEMORY_FILE):
            with open(MEMORY_FILE, "r", encoding="utf-8") as f:
                return f.read().strip()
    except Exception:
        pass
    return ""


def get_tools():
    """Get tools for LLM binding.

    Filters out complex Sheets tools that cause schema validation errors with Gemini.
    Sheets operations are better handled through the multi-agent system.
    """
    existing_tools = [
        get_current_date_time,
        web_search,
        pwd,
        open_application,
        read_memory,
        save_to_memory,
        append_to_memory,
    ]

    return existing_tools


def get_tool_map():
    """Get mapping of tool names to tool objects.

    Note: Sheets tools are excluded from direct tool map as they're better
    handled through the multi-agent system due to complex schema requirements.
    """
    tool_map = {
        "get_current_date_time": get_current_date_time,
        "web_search": web_search,
        "open_application": open_application,
        "read_memory": read_memory,
        "save_to_memory": save_to_memory,
        "append_to_memory": append_to_memory,
    }

    return tool_map