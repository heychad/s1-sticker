#!/bin/zsh
# @raycast.schemaVersion 1
# @raycast.title Ask AI and Print to Vretti
# @raycast.mode compact
# @raycast.packageName S1 Sticker
# @raycast.icon 🏷️
# @raycast.argument1 { "type": "text", "placeholder": "Describe 4×6 artwork" }
# @raycast.description Generate artwork using your API key, then print one Vretti label.
set -euo pipefail
exec "$HOME/Applications/S1 Sticker.app/Contents/MacOS/S1Sticker" --vretti-ai-image "$1" --compact
