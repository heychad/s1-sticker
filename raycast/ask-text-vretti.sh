#!/bin/zsh
# @raycast.schemaVersion 1
# @raycast.title Ask AI Text and Print to Vretti
# @raycast.mode compact
# @raycast.packageName S1 Sticker
# @raycast.icon 🏷️
# @raycast.argument1 { "type": "text", "placeholder": "Describe a 4×6 label or worksheet" }
# @raycast.description Generate text using your API key, then print one Vretti label.
set -euo pipefail
exec "$HOME/Applications/S1 Sticker.app/Contents/MacOS/S1Sticker" --vretti-ai-text "$1" --compact
