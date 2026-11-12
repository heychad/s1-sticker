#!/usr/bin/env python3
"""Choose an existing Apple development identity; never inspect private key data."""
import re
import subprocess
import sys
from pathlib import Path

result=subprocess.run(["security","find-identity","-v","-p","codesigning"],capture_output=True,text=True,check=True)
identities=re.findall(r'\) ([A-Fa-f0-9]{40}) "(Apple Development:[^"]+)"',result.stdout)
if not identities:
    sys.exit("No Apple Development signing identity is available. Add the development account in Xcode before rebuilding.")
selection=Path(__file__).resolve().parent.parent/".mac-signing-identity"
available={fingerprint for fingerprint,_ in identities}
if selection.exists():
    chosen=selection.read_text().strip()
    if chosen not in available:
        sys.exit("The configured Mac signing identity is unavailable. Restore it in Xcode before rebuilding.")
else:
    chosen=identities[0][0]
    selection.write_text(chosen+"\n")
print(chosen)
