import os
import subprocess
import shutil
import threading
from agent.settings.settings import TTS_DIR

def speak(text):
    """Stream audio directly from Piper to Speakers (No WAV file saved)"""
    def _speak_thread():
        model_path = os.path.join(TTS_DIR, "jarvis.onnx")

        print(f"Using Piper model at: {model_path}")
        
        if not shutil.which("play"):
            print("Error: 'play' command not found. Please run: brew install sox")
            return

        piper_cmd = [
            "piper",
            "--model", model_path,
            "--output_file", "-" 
        ]

        player_cmd = ["play", "-"]

        try:
            player_process = subprocess.Popen(
                player_cmd, 
                stdin=subprocess.PIPE,
                stderr=subprocess.DEVNULL # Hide SoX text output
            )

            # Start the Piper process (sending output to Player)
            piper_process = subprocess.Popen(
                piper_cmd,
                stdin=subprocess.PIPE,
                stdout=player_process.stdin, # PIPE DIRECTLY TO PLAYER
                stderr=subprocess.DEVNULL  # Hide Piper text output
            )

            # Send the text to Piper
            piper_process.communicate(input=text.encode('utf-8'))
            
            player_process.stdin.close()
            player_process.wait()

        except Exception as e:
            print(f"Error streaming audio: {e}")

    threading.Thread(target=_speak_thread).start()