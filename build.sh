#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/build/XSpace.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/XSpace"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Assets/XSpace.icns" "$APP/Contents/Resources/XSpace.icns"
cp "$ROOT/Assets/default-wallpaper.jpg" "$APP/Contents/Resources/default-wallpaper.jpg"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "$APP"
