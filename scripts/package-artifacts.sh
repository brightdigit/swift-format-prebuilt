#!/usr/bin/env bash
set -euo pipefail

OS="${1:?Usage: package-artifacts.sh <macos|linux> <universal|x86_64|aarch64>}"
ARCH="${2:?}"
VERSION="${SWIFT_FORMAT_VERSION:?SWIFT_FORMAT_VERSION must be set}"

TARBALL="swift-format-${VERSION}-${OS}-${ARCH}.tar.gz"

if [[ "$OS" == "macos" ]]; then
  BINARY=".build/apple/Products/Release/swift-format"
else
  BINARY=".build/${ARCH}-swift-linux-musl/release/swift-format"
fi

cp "$BINARY" swift-format
chmod +x swift-format
tar czf "$TARBALL" swift-format
rm swift-format

echo "Created: $TARBALL"
ls -lh "$TARBALL"
