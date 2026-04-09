# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project purpose

This repo (`brightdigit/swift-format-prebuilt`) hosts prebuilt binaries of [Apple's swift-format](https://github.com/swiftlang/swift-format) and the CI/CD pipeline that produces them. It exists to enable `mise use apple-swift-format@602.0.0` — zero-dependency installation of Apple's official Swift formatter without a Swift toolchain on the machine.

The full specification is in `prd-mise-swift-format.md`.

## Architecture overview

The project has two interrelated components:

1. **Binary build pipeline** — GitHub Actions workflows that compile swift-format from source and publish release assets to this repo's GitHub Releases.
2. **Mise registry entry** — A PR to the mise registry (`registry/*.toml`) that points to this repo's releases as the `github` backend, with `spm:swiftlang/swift-format` as a source-build fallback.

## Build targets and artifact naming

Four artifacts per release:

| Asset filename | Description |
|---|---|
| `swift-format-{version}-macos-universal.tar.gz` | macOS fat binary (arm64 + x86_64) |
| `swift-format-{version}-linux-x86_64.tar.gz` | Linux x86_64, statically linked (musl) |
| `swift-format-{version}-linux-aarch64.tar.gz` | Linux aarch64, statically linked (musl) |
| `swift-format-{version}-checksums.txt` | SHA256 checksums for all three tarballs |

Each tarball contains a single binary named `swift-format`.

## Build commands per target

| Target | Runner | Command |
|---|---|---|
| macOS universal | `macos-14` | `xcrun swift build -c release --arch arm64 --arch x86_64` |
| Linux x86_64 | `macos-14` (cross-compile) | `swift build -c release --swift-sdk x86_64-swift-linux-musl` |
| Linux aarch64 | `macos-14` (cross-compile) | `swift build -c release --swift-sdk aarch64-swift-linux-musl` |

All Linux builds use the Swift Static Linux SDK (musl) for fully static binaries with zero external dependencies. The binary output is at `.build/release/swift-format`.

## Version scheme

swift-format encodes the target Swift release in its version number: `508.0.0` = Swift 5.8, `602.0.0` = Swift 6.2. No `v` prefix is used. Versions 508.0.0+ are in scope; pre-5.8 require exact toolchain matching and are excluded. Pre-release tags contain the string `prerelease` and are excluded from automated builds.

## Upstream version tracking

A scheduled workflow polls `swiftlang/swift-format` GitHub releases (daily cron), detects new stable tags, and triggers the build+publish pipeline. The goal is to publish new binaries within 24 hours of an upstream tag.

## Mise registry entry

```toml
[tools.apple-swift-format]
description = "Apple's official formatting technology for Swift source code"
backends = ["github:brightdigit/swift-format-prebuilt", "spm:swiftlang/swift-format"]
test = ["swift-format --version", "{{version}}"]
os = ["macos", "linux"]
```

The name `apple-swift-format` is intentional — `swiftformat` in the mise registry already refers to nicklockwood/SwiftFormat (a different tool).

## Reference implementation

SwiftLint (`realm/SwiftLint`) is the model to follow for artifact structure. Its assets use `{tool}_{os}_{arch}.{format}` naming and are registered in mise via both `aqua` and `github` backends.

## Scope boundaries

**Phase 1 (in scope):** macOS universal + Linux x86_64/aarch64 binaries, SHA256 checksums, automated tracking, mise registry PR for versions 508.0.0+.

**Out of scope:** Windows (requires CMake, not SPM), versions before 508.0.0, pre-release builds (unless manually triggered).
