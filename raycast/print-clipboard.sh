#!/bin/zsh
# @raycast.schemaVersion 1
# @raycast.title Print Clipboard to S1
# @raycast.mode compact
# @raycast.packageName S1 Sticker
# @raycast.icon 🧾
# @raycast.description Print the copied image, file, or text directly to your S1. No print dialog.
set -euo pipefail
exec "$HOME/Applications/S1 Sticker.app/Contents/MacOS/S1Sticker" --clipboard --compact
