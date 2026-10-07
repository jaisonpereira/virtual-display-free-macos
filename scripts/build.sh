#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="build/virtual-display-free-macos.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O2 \
  -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 \
  -framework Cocoa -framework CoreGraphics \
  src/main.m src/Options.m -o "$app/Contents/MacOS/virtual-display-free-macos"
cp resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
printf 'Aplicativo compilado: %s\n' "$app"
