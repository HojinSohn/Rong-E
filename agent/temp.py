import subprocess
import json

# Try to get more detailed account info
script = '''
tell application "Mail"
    set accountList to {}
    repeat with acc in accounts
        set end of accountList to {name:name of acc, emailAddresses:email addresses of acc}
    end repeat
    return accountList
end tell
'''

result = subprocess.run(['osascript', '-e', script], 
                       capture_output=True, 
                       text=True)
print("Output:", result.stdout)
print("Error:", result.stderr)