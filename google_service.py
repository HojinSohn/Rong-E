import os
import datetime
import json
import gspread

# Load configuration
CONFIG_FILE = 'config.json'

def load_config():
    if not os.path.exists(CONFIG_FILE):
        raise FileNotFoundError(f"Configuration file {CONFIG_FILE} not found.")
    with open(CONFIG_FILE, 'r') as f:
        return json.load(f)

config = load_config()
SPREADSHEET_ID = config.get('spreadsheet_id')
SHEET_NAME = config.get('sheet_name')
SHEETS_CREDS_FILE = config.get('credentials_file', 'credentials.json')

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
            
            # 1. Read existing data (Columns A, B, C)
            # Using get_values() is safer across versions than .get()
            rows = sheet.get_values("A2:C1000") 
            
            target_row_index = -1
            
            # 2. Find first empty row
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

            # 3. Prepare Data
            current_date = datetime.datetime.now().strftime("%m/%d/%Y")
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

            # 4. Update the row
            # gspread v6.0+ syntax: update(values, range_name=...)
            range_notation = f"A{target_row_index}:H{target_row_index}"
            sheet.update(values=[row_data], range_name=range_notation)
            
            print(f"Successfully inserted data at Row {target_row_index}")
            return True

        except Exception as e:
            print(f"Sheet Error: {e}")
            return False


if __name__ == "__main__":
    try:
        print("Attempting to connect...")
        gc = gspread.service_account(filename="credentials.json")

    except Exception as e:
        print("\n--- CONNECTION FAILED ---")
        print(e)
    try:
        tracker = JobTracker()
        tracker.find_and_update_empty_row("META", "AI Intern", "https://www.metacareers.com")
    except Exception as e:
        print(f"Critical Failure: {e}")