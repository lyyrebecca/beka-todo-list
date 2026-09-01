#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

BIN="${TMPDIR:-/tmp}/LiquidTodoTests-$$"
trap 'rm -f "$BIN"' EXIT

xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  -o "$BIN" Sources/TodoItem.swift Sources/TodoDraft.swift Sources/TodoStore.swift \
  Tests/TodoStoreTests.swift
"$BIN"

grep -q 'isMovableByWindowBackground = false' Sources/AppDelegate.swift
grep -q 'let controlsWidth: CGFloat = 136' Sources/AppDelegate.swift
grep -q 'Button(action: beginEditing)' Sources/WidgetView.swift
grep -q 'func minimizeWidget()' Sources/AppDelegate.swift
grep -q 'func restoreWidget()' Sources/AppDelegate.swift
grep -q 'Text("干")' Sources/WidgetView.swift
grep -q 'static let miniSize: CGFloat = 48' Sources/AppDelegate.swift
grep -q 'context.duration = windowMotionDuration' Sources/AppDelegate.swift
grep -q 'window.hasShadow = false' Sources/AppDelegate.swift
! grep -q 'window.hasShadow = true' Sources/AppDelegate.swift
grep -q 'snapMiniFrameToNearestEdge' Sources/AppDelegate.swift
grep -q 'override var canBecomeMain: Bool { true }' Sources/WidgetWindow.swift
grep -q 'makeKeyAndOrderFront' Sources/WidgetWindow.swift
grep -q 'func activateForTextInput()' Sources/AppDelegate.swift
echo "✅ Interaction regression guards: drag, header buttons, editing, mini mode"
