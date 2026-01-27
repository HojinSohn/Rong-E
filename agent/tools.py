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

def get_tools():
    """Get tools for LLM binding.
    
    Filters out complex Sheets tools that cause schema validation errors with Gemini.
    Sheets operations are better handled through the multi-agent system.
    """
    existing_tools = [get_current_date_time, web_search, pwd, open_application]
    
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
    }

    return tool_map