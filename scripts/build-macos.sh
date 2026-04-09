#!/usr/bin/env bash
set -euo pipefail

xcrun swift build -c release --arch arm64 --arch x86_64

echo "Build complete."
file .build/apple/Products/Release/swift-format
lipo -info .build/apple/Products/Release/swift-format
