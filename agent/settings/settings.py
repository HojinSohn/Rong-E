import os

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TTS_DIR = os.path.join(BASE_DIR, "tts")
CONFIG_DIR = os.path.join(BASE_DIR, "config")
PROMPTS_DIR = os.path.join(BASE_DIR, "prompts")