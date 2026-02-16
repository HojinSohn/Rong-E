import json
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
from enum import Enum
from typing import Optional, Any
from pydantic import BaseModel, Field
from langchain.tools import tool
from agent.models.model import SheetAction, SheetToolInput
from google.auth.transport.requests import Request

# Move this OUTSIDE the class
@tool(args_schema=SheetToolInput)
def manage_spreadsheet(
    action: SheetAction, 
    range_name: str, 
    spreadsheet_id: str = None, 
    values_json: str = None
) -> str:
    """
    The Master Tool for Google Sheets.
    Can read data, append rows, update cells, or create new sheets.
    Always provide valid JSON for 'values_json' when writing data.
    """
    service = build_sheets_service(credentials=AuthManager._current_credentials)
    values = []
    if values_json:
        try:
            values = json.loads(values_json)
        except json.JSONDecodeError:
            return f"❌ Error: The data provided in 'values_json' was not valid JSON. You sent: {values_json}"

    try:
        if "!" in range_name:
            sheet_part, cell_part = range_name.split("!", 1)
            if " " in sheet_part and not sheet_part.startswith("'"):
                range_name = f"'{sheet_part}'!{cell_part}"
        elif " " in range_name and not range_name.startswith("'"):
            range_name = f"'{range_name}'"

        if action == SheetAction.READ:
            if not spreadsheet_id: return "❌ Error: spreadsheet_id is required for reading."
            result = service.spreadsheets().values().get(
                spreadsheetId=spreadsheet_id, range=range_name
            ).execute()
            rows = result.get('values', [])
            return f"✅ Read {len(rows)} rows from {range_name}. Data: {json.dumps(rows)}"

        elif action == SheetAction.APPEND:
            if not spreadsheet_id or not values: return "❌ Error: spreadsheet_id and values_json are required."
            body = {'values': values}
            result = service.spreadsheets().values().append(
                spreadsheetId=spreadsheet_id, range=range_name,
                valueInputOption="USER_ENTERED", body=body
            ).execute()
            return f"✅ Appended {result.get('updates').get('updatedRows')} rows."

        elif action == SheetAction.UPDATE:
            if not spreadsheet_id or not values: return "❌ Error: spreadsheet_id and values_json are required."
            body = {'values': values}
            result = service.spreadsheets().values().update(
                spreadsheetId=spreadsheet_id, range=range_name,
                valueInputOption="USER_ENTERED", body=body
            ).execute()
            return f"✅ Updated {result.get('updatedCells')} cells."

        elif action == SheetAction.CREATE:
            spreadsheet = {'properties': {'title': range_name}}
            spreadsheet = service.spreadsheets().create(body=spreadsheet, fields='spreadsheetId').execute()
            new_id = spreadsheet.get('spreadsheetId')
            return f"✅ Created new spreadsheet. Title: '{range_name}'. ID: {new_id}"

    except Exception as e:
        return f"❌ API Error: {str(e)}"

    return "❌ Action not recognized."


class AuthManager():
    """
    Manages Google API authentication and provides toolkits for Gmail, Calendar, and Sheets.
    """
    _current_credentials = None  # Class variable to store credentials for the tool

    def __init__(self):
        self.credentials = None
        self.gmail_toolkit = None
        self.calendar_toolkit = None
        self.sheets_toolkit = None
        # Stored spreadsheet configurations from the UI
        self.spreadsheet_configs: list[dict] = []

    def check_connected(self) -> bool:
        """
        Checks if the user is authenticated with Google APIs.
        """
        return self.credentials is not None

    async def authenticate(self, token_file: str = None, client_secrets_file: str = None):
        """
        Authenticates with Google APIs and initializes toolkits.
        """
        self.credentials = get_google_credentials(
            token_file=token_file,
            scopes=["https://www.googleapis.com/auth/calendar", "https://mail.google.com/", "https://www.googleapis.com/auth/spreadsheets"], 
            client_secrets_file=client_secrets_file
        )

        # check if credentials exist and are valid
        if self.credentials and not self.credentials.valid:
            if self.credentials.expired and self.credentials.refresh_token:
                print("Token expired, refreshing...")
                try:
                    self.credentials.refresh(Request())
                    
                    if token_file:
                        with open(token_file, 'w') as token:
                            token.write(self.credentials.to_json())
                            print("Refreshed credentials saved to disk.")
                            
                except Exception as e:
                    print(f"Error refreshing token: {e}")
                    # Throw exception to trigger full login flow
                    raise e
            else:
                print("Credentials invalid and cannot be refreshed.")
                # Throw exception to trigger full login flow
                raise Exception("Invalid credentials.")
        
        # Refresh credentials if expired
        if self.credentials and self.credentials.expired and self.credentials.refresh_token:
            self.credentials.refresh(Request())

    def get_gmail_toolkit(self):
        """
        Authenticates with Gmail and returns the LangChain Toolkit.
        On first run, this opens a browser for OAuth login.
        """
        api_resource = build_gmail_service(credentials=self.credentials)
        toolkit = GmailToolkit(api_resource=api_resource)
        
        return toolkit

    def get_calendar_toolkit(self):
        """
        Authenticates with Google Calendar and returns the LangChain Toolkit.
        On first run, this opens a browser for OAuth login.
        """
        api_resource = build_calendar_service(credentials=self.credentials)
        toolkit = CalendarToolkit(api_resource=api_resource)
        
        return toolkit

    # Only give access to read-only Gmail tools
    def get_access_gmail_tools(self):
        access_tools = []
        toolkit = self.get_gmail_toolkit()
        for tool in toolkit.get_tools():
            # give only access to read access tools
            if tool.name == "search_gmail" or tool.name == "get_gmail_message" or tool.name == "get_gmail_thread":
                access_tools.append(tool)
        return access_tools

    # Give full access to calendar tools (with JSON string arg fix)
    def get_calendar_tools(self):
        access_tools = []
        toolkit = self.get_calendar_toolkit()
        for t in toolkit.get_tools():
            access_tools.append(t)
        return access_tools

    @staticmethod
    def _wrap_tool_with_json_fix(t):
        """Wrap a tool so that any string arg that looks like JSON gets parsed into a dict/list."""
        original_run = t._run

        def patched_run(*args, **kwargs):
            fixed_kwargs = {}
            for k, v in kwargs.items():
                if isinstance(v, str):
                    try:
                        parsed = json.loads(v)
                        if isinstance(parsed, (dict, list)):
                            fixed_kwargs[k] = parsed
                            continue
                    except (json.JSONDecodeError, ValueError):
                        pass
                fixed_kwargs[k] = v
            return original_run(*args, **fixed_kwargs)

        t._run = patched_run
        return t

    def get_google_tools(self):
        """
        Returns the combined list of Google tools: Gmail (read-only), Calendar, and Sheets.
        """
        AuthManager._current_credentials = self.credentials  # Update credentials for the tool
        all_tools = []
        all_tools.extend(self.get_access_gmail_tools())
        all_tools.extend(self.get_calendar_tools())
        all_tools.append(manage_spreadsheet)  # Use the standalone function
        return all_tools

    def get_sheet_tabs(self, spreadsheet_id: str) -> dict:
        """
        Fetches the list of sheet/tab names from a Google Spreadsheet.
        Returns: {"success": True, "title": str, "tabs": [str]} or {"success": False, "error": str}
        """
        if self.credentials is None:
            return {"success": False, "error": "Not authenticated with Google"}

        try:
            service = build_sheets_service(credentials=self.credentials)
            spreadsheet = service.spreadsheets().get(spreadsheetId=spreadsheet_id).execute()

            title = spreadsheet.get('properties', {}).get('title', 'Untitled')
            sheets = spreadsheet.get('sheets', [])
            tabs = [sheet.get('properties', {}).get('title', 'Sheet') for sheet in sheets]

            return {
                "success": True,
                "title": title,
                "tabs": tabs
            }
        except Exception as e:
            return {"success": False, "error": str(e)}

    def set_spreadsheet_configs(self, configs: list[dict]):
        """
        Store spreadsheet configurations from the UI.
        Each config should have: alias, url, sheetID, selectedTab, description
        """
        self.spreadsheet_configs = configs
        print(f"📊 Stored {len(configs)} spreadsheet configuration(s)")

    def get_spreadsheet_context(self) -> str:
        """
        Returns a formatted string of available spreadsheets for inclusion in agent context.
        """
        if not self.spreadsheet_configs:
            return ""

        lines = ["### Available Google Spreadsheets", "The user has configured the following spreadsheets for quick access:"]
        for config in self.spreadsheet_configs:
            alias = config.get("alias", "Unknown")
            sheet_id = config.get("sheetID", "")
            tab = config.get("selectedTab", "Sheet1")
            description = config.get("description", "")
            lines.append(f"- **{alias}**: ID=`{sheet_id}`, Tab=`{tab}`")
            if description:
                lines.append(f"  Description: {description}")

        lines.append("\nWhen the user refers to a spreadsheet by alias, use the corresponding spreadsheet_id and tab name.")
        return "\n".join(lines)
