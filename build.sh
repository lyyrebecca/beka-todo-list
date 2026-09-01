#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="LiquidTodo.app"
BIN_DIR="$APP/Contents/MacOS"
BUILD_DIR=".build/release"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCHS=(arm64 x86_64)

rm -rf "$APP" "$BUILD_DIR"
mkdir -p "$BIN_DIR" "$APP/Contents/Resources" "$BUILD_DIR"

echo "▶ 编译 Universal macOS 二进制…"
for ARCH in "${ARCHS[@]}"; do
  xcrun swiftc -O -whole-module-optimization -swift-version 5 \
    -sdk "$SDK" \
    -target "${ARCH}-apple-macos14.0" \
    -o "$BUILD_DIR/LiquidTodo-$ARCH" Sources/*.swift
done
lipo -create "$BUILD_DIR/LiquidTodo-arm64" "$BUILD_DIR/LiquidTodo-x86_64" \
  -output "$BIN_DIR/LiquidTodo"

cp Info.plist "$APP/Contents/"
cp Assets/LiquidTodo.icns "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"

plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP"
ARCH_OUTPUT="$(lipo -archs "$BIN_DIR/LiquidTodo")"
[[ "$ARCH_OUTPUT" == *arm64* && "$ARCH_OUTPUT" == *x86_64* ]]

echo "✔ Universal 构建完成：$(pwd)/$APP"
