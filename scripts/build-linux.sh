#!/usr/bin/env bash
set -euo pipefail

ARCH="${1:?Usage: build-linux.sh <x86_64|aarch64>}"
SWIFT_SDK="${ARCH}-swift-linux-musl"

swift build -c release --swift-sdk "$SWIFT_SDK"

BINARY=".build/${SWIFT_SDK}/release/swift-format"
echo "Build complete: $BINARY"
file "$BINARY"
