#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun swiftc -swift-version 5 Sources/Routing.swift Tests/main.swift -o build/routing-tests
build/routing-tests
