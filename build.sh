#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/build/XSpace.app"
CORE="$ROOT/Vendor/MousecapeCore"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Mousecape 光标核心为 Objective-C 实现，与 Swift 源码一起编译
swiftc -O -import-objc-header "$ROOT/Sources/XSpace-Bridging-Header.h" -I "$CORE" \
    "$ROOT"/Sources/*.swift "$CORE"/*.m -o "$APP/Contents/MacOS/XSpace"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Assets/XSpace.icns" "$APP/Contents/Resources/XSpace.icns"
cp "$ROOT/Assets/default-wallpaper.jpg" "$APP/Contents/Resources/default-wallpaper.jpg"
cp "$ROOT/Resources/7zz" "$APP/Contents/Resources/7zz"
cp "$CORE/LICENSE" "$APP/Contents/Resources/Mousecape-LICENSE.txt"
cp "$CORE/NOTICE.md" "$APP/Contents/Resources/Mousecape-NOTICE.txt"
chmod +x "$APP/Contents/Resources/7zz"
mkdir -p "$APP/Contents/Resources/sevenzip"
cp "$ROOT"/Assets/sevenzip/*.png "$APP/Contents/Resources/sevenzip/"
mkdir -p "$APP/Contents/Resources/FileIcons"
cp "$ROOT"/Assets/FileIcons/*.png "$APP/Contents/Resources/FileIcons/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 7-Zip 弹窗的独立 Dock 图标助手：独立进程才能在 Dock 中单独出现一个 7-Zip 图标
HELPER_SRC="$ROOT/Helper/SevenZipDock"
HELPER="$APP/Contents/Resources/SevenZipDock.app"
mkdir -p "$HELPER/Contents/MacOS" "$HELPER/Contents/Resources"
swiftc -O "$HELPER_SRC/main.swift" -o "$HELPER/Contents/MacOS/SevenZipDock"
cp "$HELPER_SRC/Info.plist" "$HELPER/Contents/Info.plist"
cp "$ROOT/Assets/sevenzip/RAR.png" "$HELPER/Contents/Resources/SevenZipDock.png"
printf 'APPL????' > "$HELPER/Contents/PkgInfo"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "$APP"
