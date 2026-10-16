#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="${TMPDIR:-/tmp}/LiquidTodoStatusItemTests-$$"
trap 'rm -f "$BIN"' EXIT
# Native AppKit checks require a macOS graphical login session.
xcrun swiftc -O -swift-version 5 -o "$BIN" \
  Sources/StatusItemPresentation.swift Tests/StatusItemPresentationTests.swift
"$BIN"
