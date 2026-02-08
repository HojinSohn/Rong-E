import os
import sys

# Detect if running as PyInstaller bundle
if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
    # Running as PyInstaller bundle - use _MEIPASS for bundled data
    BASE_DIR = sys._MEIPASS
else:
    # Running as normal Python script
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TTS_DIR = os.path.join(BASE_DIR, "tts")
CONFIG_DIR = os.path.join(BASE_DIR, "config")
PROMPTS_DIR = os.path.join(BASE_DIR, "prompts")

# Memory directory - stored in user's home for persistence across app updates
MEMORY_DIR = os.path.join(os.path.expanduser("~"), ".ronge", "memory")
MEMORY_FILE = os.path.join(MEMORY_DIR, "memory.md")

# Ensure memory directory exists
os.makedirs(MEMORY_DIR, exist_ok=True)