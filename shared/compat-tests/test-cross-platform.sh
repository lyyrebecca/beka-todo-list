#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/LiquidTodo-CrossBackup.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT
DOTNET="${DOTNET:-dotnet}"
"$DOTNET" run --project shared/compat-tests/CrossPlatformBackup.csproj -c Release -- write "$ROOT"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -o "$ROOT/SwiftBackupRoundTrip" \
  Sources/TodoItem.swift Sources/TodoDraft.swift Sources/TodoBackup.swift Sources/TodoHierarchy.swift Sources/TodoStore.swift \
  shared/compat-tests/BackupRoundTrip.swift
"$ROOT/SwiftBackupRoundTrip" "$ROOT"
"$DOTNET" run --project shared/compat-tests/CrossPlatformBackup.csproj -c Release --no-build -- verify "$ROOT"
