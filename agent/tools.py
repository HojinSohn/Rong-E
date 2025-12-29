import datetime
import os
import platform
from langchain_core.tools import tool
from langchain_community.tools import DuckDuckGoSearchRun
from backend.utils.file_utils import display_directory_tree, read_file_data, collect_file_paths, separate_files_by_type
from backend.services.google_service import gmail_tools, tracker, calendar_tools
from backend.services.rag import rag
import datetime
import os
import subprocess
from typing import List
from backend.models.model import (
    JobApplicationSchema, 
    WebSearchSchema, 
    ListDirectorySchema, 
    ReadFileSchema, 
    CollectFilesSchema, 
    SeparateFilesSchema, 
    OpenApplicationSchema, 
    KBSearchSchema
)

search = DuckDuckGoSearchRun()

@tool("web_search", description="Useful for searching the internet for current events or facts.", args_schema=WebSearchSchema)
def web_search(query: str):
    """Useful for searching the internet for current events or facts."""
    return search.run(query)

@tool("record_job_application", description="Logs a job application to the Google Sheet.", args_schema=JobApplicationSchema)
def record_job_application(company: str, position: str, url: str) -> str:
    """
    Logs an action or data point to the Google Sheet.
    Useful for saving research results, tracking tasks, or keeping a history.
    
    Args:
        company (str): The name of the company.
        position (str): The job position applied for.
        url (str): The URL of the job posting.
    """
    success = tracker.find_and_update_empty_row(company, position, url)
    if success:
        return f"Logged application for {position} at {company}."
    else:
        return "Failed to log the job application."

@tool("get_current_date_time", description="Returns the current local date and time.")
def get_current_date_time():
    """Returns the current local date and time."""
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

@tool("list_directory", description="Lists the directory tree of a given path.", args_schema=ListDirectorySchema)
def list_directory(path: str):
    """Lists the directory tree of a given path."""
    display_directory_tree(path)
    return f"Displayed directory tree for {path}"

@tool("read_file", description="Reads the content of a file based on its type.", args_schema=ReadFileSchema)
def read_file(path: str):
    """Reads the content of a file based on its type."""
    content = read_file_data(path)
    if content is not None:
        return content
    else:
        return f"Unsupported file type or error reading file: {path}"
    
@tool("collect_files", description="Collects all file paths from a directory or single file.", args_schema=CollectFilesSchema)
def collect_files(path: str):
    """Collects all file paths from a directory or single file."""
    file_paths = collect_file_paths(path)
    return file_paths

@tool("separate_files", description="Separates files into image and text categories.", args_schema=SeparateFilesSchema)
def separate_files(file_paths: List[str]):
    """Separates files into image and text categories."""
    image_files, text_files = separate_files_by_type(file_paths)
    return {
        "image_files": image_files,
        "text_files": text_files
    }

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

@tool("search_knowledge_base", description="Searches the knowledge base for information. Must be used when information regarding Hojin's personal information, projects, files, or context-sensitive data.", args_schema=KBSearchSchema)
def kb_search(query: str):
    output = rag.search_knowledge_base(query)
    return output

def get_tools():
    existing_tools = [get_current_date_time, web_search, record_job_application, pwd, open_application, kb_search]
    tools = existing_tools + gmail_tools + calendar_tools
    return tools

def get_tool_map():
    tool_map = {
        "get_current_date_time": get_current_date_time, 
        "web_search": web_search,
        "record_job_application": record_job_application,
        "open_application": open_application,
        "search_knowledge_base": kb_search,
    }

    for tool in gmail_tools:
        tool_map[tool.name] = tool

    for tool in calendar_tools:
        tool_map[tool.name] = tool

    return tool_map