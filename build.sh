#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
DEST="${1:-build}"
mkdir -p "$DEST/BrowserRouter.app/Contents/MacOS"
cp Info.plist "$DEST/BrowserRouter.app/Contents/Info.plist"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 Sources/Routing.swift Sources/Configuration.swift Sources/Delivery.swift Sources/main.swift -o "$DEST/BrowserRouter.app/Contents/MacOS/BrowserRouter"
codesign --force --sign - "$DEST/BrowserRouter.app"
printf 'Built %s/BrowserRouter.app\n' "$DEST"
