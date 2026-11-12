#!/bin/zsh
# @raycast.schemaVersion 1
# @raycast.title Ask AI and Print to S1
# @raycast.mode compact
# @raycast.packageName S1 Sticker
# @raycast.icon 🎨
# @raycast.argument1 { "type": "text", "placeholder": "Describe the image or sticker to print" }
# @raycast.description Generate thermal-ready artwork with your saved OpenAI key, then print once. Uses API credits.
set -euo pipefail
exec "$HOME/Applications/S1 Sticker.app/Contents/MacOS/S1Sticker" --ai-image "$1" --compact
