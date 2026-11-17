#!/bin/zsh
# @raycast.schemaVersion 1
# @raycast.title Print File to Vretti
# @raycast.mode compact
# @raycast.packageName S1 Sticker
# @raycast.icon 🏷️
# @raycast.argument1 { "type": "text", "placeholder": "Absolute image, PDF, or text file path" }
# @raycast.description Print one 4×6 label. PDFs use their first page.
set -euo pipefail
exec "$HOME/Applications/Vretti Print.app/Contents/MacOS/VrettiPrint" --print "$1"
