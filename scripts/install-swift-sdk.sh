#!/usr/bin/env bash
set -euo pipefail

SDK_URL="${SWIFT_SDK_URL:?SWIFT_SDK_URL must be set}"
SDK_CHECKSUM="${SWIFT_SDK_CHECKSUM:?SWIFT_SDK_CHECKSUM must be set}"

if swift sdk list 2>/dev/null | grep -q "swift-linux-musl"; then
  echo "Swift Static Linux SDK already installed, skipping."
  exit 0
fi

swift sdk install "$SDK_URL" --checksum "$SDK_CHECKSUM"
