#!/bin/zsh
# @raycast.schemaVersion 1
# @raycast.title Print Clipboard to Vretti
# @raycast.mode compact
# @raycast.packageName S1 Sticker
# @raycast.icon 🏷️
# @raycast.description Print a copied image, file, or text as one 4×6 label.
set -euo pipefail
exec "$HOME/Applications/Vretti Print.app/Contents/MacOS/VrettiPrint" --clipboard --dither
