import datetime
import os
import platform
from langchain_core.tools import tool
from langchain_community.tools import DuckDuckGoSearchRun
from google_service import JobTracker

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
