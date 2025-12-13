import datetime
import os
import platform
from langchain_core.tools import tool
from langchain_community.tools import DuckDuckGoSearchRun
from google_service import JobTracker
from file_utils import read_file_data, display_directory_tree, collect_file_paths, separate_files_by_type
from memory import memory

search = DuckDuckGoSearchRun()

@tool("web_search", description="Useful for searching the internet for current events or facts.")
def web_search(query: str):
    """Useful for searching the internet for current events or facts."""
    return search.run(query)

@tool("record_job_application", description="Logs a job application to the Google Sheet.")
def record_job_application(company: str, position: str, url: str) -> str:
    """
    Logs an action or data point to the Google Sheet.
    Useful for saving research results, tracking tasks, or keeping a history.
    
    Args:
        company (str): The name of the company.
        position (str): The job position applied for.
        url (str): The URL of the job posting.
    """
    tracker = JobTracker()
    success = tracker.find_and_update_empty_row(company, position, url)
    if success:
        return f"Logged application for {position} at {company}."
    else:
        return "Failed to log the job application."

@tool("get_current_time", description="Returns the current local time.")
def get_current_time():
    """Returns the current local time."""
    return datetime.datetime.now().strftime("%H:%M:%S")

@tool("list_directory", description="Lists the directory tree of a given path.")
def list_directory(path: str):
    """Lists the directory tree of a given path."""
    display_directory_tree(path)
    return f"Displayed directory tree for {path}"

@tool("read_file", description="Reads the content of a file based on its type.")
def read_file(path: str):
    """Reads the content of a file based on its type."""
    content = read_file_data(path)
    if content is not None:
        return content
    else:
        return f"Unsupported file type or error reading file: {path}"
    
@tool("collect_files", description="Collects all file paths from a directory or single file.")
def collect_files(path: str):
    """Collects all file paths from a directory or single file."""
    file_paths = collect_file_paths(path)
    return file_paths

@tool("separate_files", description="Separates files into image and text categories.")
def separate_files(file_paths: list):
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

@tool("get_page_content", description="Returns the current page content and URL.")
def get_page_content():
    """Returns the current page content and URL."""
    content, url = memory.get_page_info()
    print(f"Page Content: {content}\nURL: {url}")
    return {"page_content": content, "url": url}

@tool("open_application", description="Opens a specified application on the system.")
def open_application(app_name: str):
    """Opens a specified application on the system."""
    try: 
        if platform.system() == "Windows":
            os.startfile(app_name)
        elif platform.system() == "Darwin":  # macOS
            os.system(f"open -a {app_name}")
        elif platform.system() == "Linux":
            os.system(f"xdg-open {app_name}")
        else:
            return f"Unsupported operating system: {platform.system()}"
    except Exception as e:
        return f"Failed to open {app_name}: {e}"
    return f"Opened {app_name}"

def get_tools():
    return [get_current_time, web_search, record_job_application, list_directory, read_file, collect_files, separate_files, pwd, get_page_content, open_application]

def get_tool_map():
    tool_map = {
        "get_current_time": get_current_time, 
        "web_search": web_search,
        "record_job_application": record_job_application, 
        "list_directory": list_directory,
        "read_file": read_file,
        "collect_files": collect_files,
        "separate_files": separate_files,
        "pwd": pwd,
        "get_page_content": get_page_content,
        "open_application": open_application
    }
    return tool_map