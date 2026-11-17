#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}/.."
app="$PWD/.build-vretti/VrettiKeepReady.app"
mkdir -p "$app/Contents/MacOS"
cp vretti/Info.plist "$app/Contents/Info.plist"
swiftc vretti/KeepReady.swift -o "$app/Contents/MacOS/VrettiKeepReady"
signing_identity="$(python3 scripts/mac_signing_identity.py)"
codesign --force --sign "$signing_identity" "$app"
codesign --verify --deep --strict "$app"
print -r -- "$app"
