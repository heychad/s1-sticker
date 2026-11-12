#!/bin/zsh
# @raycast.schemaVersion 1
# @raycast.title Print Text to S1
# @raycast.mode compact
# @raycast.packageName S1 Sticker
# @raycast.icon 🧾
# @raycast.argument1 { "type": "text", "placeholder": "Text to print" }
# @raycast.description Type a label and print it immediately.
set -euo pipefail
exec "$HOME/Applications/S1 Sticker.app/Contents/MacOS/S1Sticker" --text "$1" --compact
