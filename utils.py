import os

def speak(text):
    # This runs the built-in Mac command
    sanitized_text = text.replace('"', '\\"')  # Simple safety for quotes
    os.system(f'say -v "Fred" -r 240 "{sanitized_text}"')
