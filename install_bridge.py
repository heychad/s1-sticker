#!/usr/bin/env python3
import os
from pathlib import Path
import plistlib
import subprocess
import sys
ROOT=Path(__file__).resolve().parent
agent=Path.home()/"Library/LaunchAgents/local.chad.s1-sticker-bridge.plist"
logs=Path.home()/"Library/Logs/S1Sticker"
agent.parent.mkdir(parents=True,exist_ok=True);logs.mkdir(parents=True,exist_ok=True)
data={"Label":"local.chad.s1-sticker-bridge","ProgramArguments":[sys.executable,str(ROOT/"bridge.py")],"WorkingDirectory":str(ROOT),"RunAtLoad":True,"KeepAlive":True,"ThrottleInterval":10,"StandardOutPath":str(logs/"bridge.log"),"StandardErrorPath":str(logs/"bridge-error.log")}
if agent.exists():
    old=plistlib.loads(agent.read_bytes())
    if old.get("ProgramArguments")!=data["ProgramArguments"]:raise SystemExit("An unrelated bridge already uses this label; left it unchanged.")
    subprocess.run(["launchctl","bootout",f"gui/{os.getuid()}",str(agent)],capture_output=True)
agent.write_bytes(plistlib.dumps(data));agent.chmod(0o600)
subprocess.run(["launchctl","bootstrap",f"gui/{os.getuid()}",str(agent)],check=True)
print("S1 bridge installed for this Mac login.")
