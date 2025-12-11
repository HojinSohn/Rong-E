import os
import subprocess
import shutil

def speak(text):
    """Stream audio directly from Piper to Speakers (No WAV file saved)"""
    base_dir = os.path.dirname(os.path.abspath(__file__))
    
    tts_dir = os.path.join(base_dir, "tts")
    model_path = os.path.join(tts_dir, "jarvis.onnx")
    
    # 1. Check if 'play' (SoX) is installed
    if not shutil.which("play"):
        print("Error: 'play' command not found. Please run: brew install sox")
        return

    # 3. Piper Command
    piper_cmd = [
        "piper",
        "--model", model_path,
        "--output_file", "-" 
    ]

    # 4. Player Command (SoX)
    player_cmd = ["play", "-"]

    try:
        # Start the Player process first (waiting for input)
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
        
        # Cleanup
        player_process.stdin.close()
        player_process.wait()

    except Exception as e:
        print(f"Error streaming audio: {e}")