#!/bin/zsh
# @raycast.schemaVersion 1
# @raycast.title Ask AI Text and Print to S1
# @raycast.mode compact
# @raycast.packageName S1 Sticker
# @raycast.icon 🧾
# @raycast.argument1 { "type": "text", "placeholder": "Describe a label, checklist, or table" }
# @raycast.description Generate crisp text or tables with your saved OpenAI key, then print once. Uses API credits.
set -euo pipefail
exec "$HOME/Applications/S1 Sticker.app/Contents/MacOS/S1Sticker" --ai-text "$1" --compact
