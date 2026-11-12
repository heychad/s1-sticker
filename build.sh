#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
mkdir -p .build-mac
xcodegen generate > .build-mac/project-generation.log
xcodebuild -project S1Sticker.xcodeproj -scheme S1Mac -configuration Release \
  -derivedDataPath .build-mac/xcode -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  build > .build-mac/mac-build.log 2>&1 || { tail -70 .build-mac/mac-build.log; exit 1; }
built_app="$PWD/.build-mac/xcode/Build/Products/Release/S1 Sticker.app"
signing_identity="$(python3 scripts/mac_signing_identity.py)"
codesign --force --sign "$signing_identity" "$built_app"
codesign --verify --deep --strict "$built_app"
if [[ "${1:-}" == '--build-only' ]]; then
  print -r -- "$built_app"
else
  installed_app="$HOME/Applications/S1 Sticker.app"
  ditto "$built_app" "$installed_app"
  print -r -- "$installed_app"
fi
