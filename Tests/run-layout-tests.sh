#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/LiquidTodo-layout-tests}"
mkdir -p "$OUT"
APP="$OUT/ArchiveLayoutTests.app"
mkdir -p "$APP/Contents/MacOS" "$OUT/module-cache"
SOURCES=()
for file in Sources/*.swift; do
  [[ "$file" == "Sources/LiquidTodoMain.swift" ]] || SOURCES+=("$file")
done
xcrun swiftc -O -whole-module-optimization -module-cache-path "$OUT/module-cache" -swift-version 5 \
  -target "$(uname -m)-apple-macos14.0" \
  -o "$APP/Contents/MacOS/ArchiveLayoutTests" "${SOURCES[@]}" Tests/ArchiveLayoutTests.swift
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.beka.liquidtodo.layout.regression</string>
<key>CFBundleExecutable</key><string>ArchiveLayoutTests</string>
<key>CFBundleName</key><string>Layout Regression</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
# Requires an interactive macOS test desktop; never substitutes for WeChat IME testing.
LIQUIDTODO_LAYOUT_REPORT="$OUT/results.json" "$APP/Contents/MacOS/ArchiveLayoutTests" --exit-after-test
