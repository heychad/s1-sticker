#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}/.."
app="$PWD/.build-vretti/VrettiPrint.app"
mkdir -p "$app/Contents/MacOS"
cp vretti/PrintInfo.plist "$app/Contents/Info.plist"
cp vretti/VrettiPrint.swift "$PWD/.build-vretti/main.swift"
swiftc "$PWD/.build-vretti/main.swift" Shared/Core/LabelMarkup.swift -o "$app/Contents/MacOS/VrettiPrint"
identity="$(python3 scripts/mac_signing_identity.py)"
codesign --force --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  ditto "$app" "$HOME/Applications/Vretti Print.app"
fi
print -r -- "$app"
