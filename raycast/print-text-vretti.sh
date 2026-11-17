#!/bin/zsh
# @raycast.schemaVersion 1
# @raycast.title Print Text to Vretti
# @raycast.mode compact
# @raycast.packageName S1 Sticker
# @raycast.icon 🏷️
# @raycast.argument1 { "type": "text", "placeholder": "Text for a 4×6 label" }
# @raycast.description Print one 4×6 text label over Bluetooth.
set -euo pipefail
label_dir="$(mktemp -d -t vretti-text)"
trap 'rm -rf -- "$label_dir"' EXIT
label_file="$label_dir/label.txt"
printf '%s\n' "$1" > "$label_file"
exec_path="$HOME/Applications/Vretti Print.app/Contents/MacOS/VrettiPrint"
"$exec_path" --print "$label_file"
