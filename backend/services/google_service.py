import os
import datetime
import json
import gspread
from langchain_google_community import CalendarToolkit, GmailToolkit
from langchain_google_community.gmail.utils import (
    build_resource_service,
)
from langchain_google_community.calendar.utils import (
    build_calendar_service,
    get_google_credentials
)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_DIR = os.path.join(BASE_DIR, 'config')

CONFIG_FILE = os.path.join(CONFIG_DIR, 'config.json')
TOKEN_FILE = os.path.join(CONFIG_DIR, 'token.json')
CREDENTIALS_FILE = os.path.join(CONFIG_DIR, 'credentials.json')

def load_config():
    if not os.path.exists(CONFIG_FILE):
        raise FileNotFoundError(f"Configuration file {CONFIG_FILE} not found.")
    with open(CONFIG_FILE, 'r') as f:
        return json.load(f)

config = load_config()
SPREADSHEET_ID = config.get('spreadsheet_id')
SHEET_NAME = config.get('sheet_name')

_creds_filename = config.get('credentials_file', 'spreadsheet_credentials.json')
SHEETS_CREDS_FILE = os.path.join(CONFIG_DIR, _creds_filename)

class JobTracker:
    def __init__(self):
        self.sheet_client = self._authenticate_sheets()
        
        # SAFETY CHECK: If auth failed, stop the program immediately
        if not self.sheet_client:
            raise ValueError("Authentication failed. Please check your credentials.json file.")

    def _authenticate_sheets(self):
        """Authenticates with Google Sheets using modern gspread method."""
        try:
            # Modern gspread can read the file directly without extra libraries
            if not os.path.exists(SHEETS_CREDS_FILE):
                print(f"Error: {SHEETS_CREDS_FILE} not found in {os.getcwd()}")
                return None
                
            client = gspread.service_account(filename=SHEETS_CREDS_FILE)
            return client
        except Exception as e:
            print(f"Auth Error: {e}")
            return None

    def find_and_update_empty_row(self, company, role, url):
        try:
            sheet = self.sheet_client.open_by_key(SPREADSHEET_ID).worksheet(SHEET_NAME)
            
            # Read existing data (Columns A, B, C)
            # Using get_values() is safer across versions than .get()
            rows = sheet.get_values("A2:C1000") 
            
            target_row_index = -1
            
            # Find first empty row
            for i, row in enumerate(rows):
                # Safe access: ensure the row has enough columns before checking
                col_a = row[0].strip() if len(row) > 0 else ""
                col_c = row[2].strip() if len(row) > 2 else ""
                
                # If Company (A) and Role (C) are empty, this is our spot
                if not col_a and not col_c:
                    target_row_index = i + 2 # +2 because we started at A2
                    break
            
            # If no gap found, append to the very end
            if target_row_index == -1:
                target_row_index = len(rows) + 2

            print(f"Found empty slot at Row {target_row_index}")

            # Prepare Data
            current_date = datetime.datetime.now().strftime("%m/%d/%Y")
            # Data columnes A to H
            # Company, Status, Position, Salary, Date Applied, URL, Rejection Reason, Note
            row_data = [
                company,                        # A
                'Submitted - Pending Response', # B
                role,                           # C
                '',                             # D
                current_date,                   # E
                url,                            # F
                'N/A',                          # G
                ''                              # H
            ]

            # Update the row
            # gspread v6.0+ syntax: update(values, range_name=...)
            range_notation = f"A{target_row_index}:H{target_row_index}"
            sheet.update(values=[row_data], range_name=range_notation)
            
            print(f"Successfully inserted data at Row {target_row_index}")
            return True

        except Exception as e:
            print(f"Sheet Error: {e}")
            return False


credentials = get_google_credentials(
    token_file=TOKEN_FILE,
    scopes=["https://www.googleapis.com/auth/calendar", "https://mail.google.com/"], 
    client_secrets_file=CREDENTIALS_FILE
)

def get_gmail_toolkit():
    """
    Authenticates with Gmail and returns the LangChain Toolkit.
    On first run, this opens a browser for OAuth login.
    """
    api_resource = build_resource_service(credentials=credentials)
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

def get_access_gmail_tools():
    access_tools = []
    toolkit = get_gmail_toolkit()
    for tool in toolkit.get_tools():
        # give only access to read access tools
        if tool.name == "search_gmail" or tool.name == "get_gmail_message" or tool.name == "get_gmail_thread":
            access_tools.append(tool)
    return access_tools

def get_access_calendar_tools():
    access_tools = []
    toolkit = get_calendar_toolkit()
    for tool in toolkit.get_tools():
        access_tools.append(tool)
    return access_tools

gmail_tools = get_access_gmail_tools()
calendar_tools = get_access_calendar_tools()
tracker = JobTracker()

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
