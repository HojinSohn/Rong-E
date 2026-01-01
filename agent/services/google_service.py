import os
from langchain_google_community import CalendarToolkit, GmailToolkit, SheetsToolkit
from langchain_google_community.gmail.utils import (
    build_gmail_service
)
from langchain_google_community.calendar.utils import (
    build_calendar_service
)
from langchain_google_community._utils import (
    get_google_credentials
)
from langchain_google_community.sheets.utils import (
    build_sheets_service
)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_DIR = os.path.join(BASE_DIR, 'config')

CONFIG_FILE = os.path.join(CONFIG_DIR, 'config.json')
TOKEN_FILE = os.path.join(CONFIG_DIR, 'token.json')
CREDENTIALS_FILE = os.path.join(CONFIG_DIR, 'credentials.json')

# Get Access Credentials for Google Services
# Gmail, Calendar, and Sheets
credentials = get_google_credentials(
    token_file=TOKEN_FILE,
    scopes=["https://www.googleapis.com/auth/calendar", "https://mail.google.com/", "https://www.googleapis.com/auth/spreadsheets"], 
    client_secrets_file=CREDENTIALS_FILE
)

def get_gmail_toolkit():
    """
    Authenticates with Gmail and returns the LangChain Toolkit.
    On first run, this opens a browser for OAuth login.
    """
    api_resource = build_gmail_service(credentials=credentials)
    toolkit = GmailToolkit(api_resource=api_resource)
    
    return toolkit

def get_calendar_toolkit():
    """
    Authenticates with Google Calendar and returns the LangChain Toolkit.
    On first run, this opens a browser for OAuth login.
    """
    api_resource = build_calendar_service(credentials=credentials)
    toolkit = CalendarToolkit(api_resource=api_resource)
    
    return toolkit

def get_sheets_toolkit():
    """
    Authenticates with Google Sheets and returns the LangChain Toolkit.
    On first run, this opens a browser for OAuth login.
    """
    api_resource = build_sheets_service(credentials=credentials)
    toolkit = SheetsToolkit(api_resource=api_resource)

    return toolkit

# Only give access to read-only Gmail tools
def get_access_gmail_tools():
    access_tools = []
    toolkit = get_gmail_toolkit()
    for tool in toolkit.get_tools():
        # give only access to read access tools
        if tool.name == "search_gmail" or tool.name == "get_gmail_message" or tool.name == "get_gmail_thread":
            access_tools.append(tool)
    return access_tools

# Give full access to calendar tools
def get_calendar_tools():
    access_tools = []
    toolkit = get_calendar_toolkit()
    for tool in toolkit.get_tools():
        access_tools.append(tool)
    return access_tools

# Give full access to sheets tools
def get_spreadsheets_tools():
    tools = []
    toolkit = get_sheets_toolkit()
    for tool in toolkit.get_tools():
        tools.append(tool)
    return tools

gmail_tools = get_access_gmail_tools()
calendar_tools = get_calendar_tools()
sheets_tools = get_spreadsheets_tools()

# Helper to see what tools are included
if __name__ == "__main__":
    toolkit = get_gmail_toolkit()
    print("Available Gmail Tools:")
    for tool in toolkit.get_tools():
        print(f"- {tool.name}: {tool.description}")

    print("\nAvailable Calendar Tools:")
    toolkit = get_calendar_toolkit()
    for tool in toolkit.get_tools():
        print(f"- {tool.name}: {tool.description}")

    toolkit = get_sheets_toolkit()
    print("\nAvailable Sheets Tools:")
    for tool in toolkit.get_tools():
        print(f"- {tool.name}: {tool.description}")
