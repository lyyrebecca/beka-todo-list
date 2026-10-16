#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/LiquidTodo-IME-focus-tests}"
mkdir -p "$OUT"
APP="$OUT/IMEFocusTests.app"
mkdir -p "$APP/Contents/MacOS" "$OUT/module-cache"
SOURCES=()
for file in Sources/*.swift; do
  [[ "$file" == "Sources/LiquidTodoMain.swift" ]] || SOURCES+=("$file")
done
xcrun swiftc -module-cache-path "$OUT/module-cache" -swift-version 5 \
  -target "$(uname -m)-apple-macos14.0" \
  -o "$APP/Contents/MacOS/IMEFocusTests" "${SOURCES[@]}" Tests/IMEFocusTests.swift
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.beka.liquidtodo.imefocus.regression</string>
<key>CFBundleExecutable</key><string>IMEFocusTests</string>
<key>CFBundleName</key><string>IME Focus Regression</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
# Requires an interactive macOS test desktop; never substitutes for WeChat IME testing.
LIQUIDTODO_FOCUS_REPORT="$OUT/results.json" "$APP/Contents/MacOS/IMEFocusTests" --exit-after-test
