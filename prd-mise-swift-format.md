# PRD: mise Plugin for Apple's swift-format with Prebuilt Binaries

## Problem statement: swift-format is bundled but not independently manageable

Since Swift 6 (Xcode 16), `swift-format` ships inside the Swift toolchain and can be invoked as `swift format` out of the box. On macOS with Xcode installed, this mostly "just works." So why build a separate distribution pipeline?

The bundled copy creates **three concrete problems** that a mise plugin solves:

### 1. Version pinning independent of the toolchain

The bundled swift-format version is locked to the Swift toolchain version. A team using Swift 6.0 cannot run the swift-format rules from 6.2 without upgrading their entire toolchain. Conversely, a project that needs to stay on an older formatter version (e.g., to avoid reformatting churn during a release freeze) has no way to pin it independently. A mise-managed binary decouples the formatter version from the compiler version, giving teams the same `mise use apple-swift-format@602.0.0` version-pinning workflow they use for every other tool.

### 2. Linux CI without a full Swift toolchain

On Linux CI runners, you typically need a full Swift toolchain Docker image (~1.5 GB) just to get access to `swift format`. There have been reports of `swift format` timing out or not working in some official Swift Docker images. A standalone statically linked binary (~15–30 MB) eliminates the toolchain dependency entirely, speeds up CI setup, and avoids these reliability issues. This is the pain point behind Issue #427, open since October 2022, which explicitly requests prebuilt release binaries for CI use.

### 3. No mise ecosystem integration

The mise dev tool manager supports 2,134+ tools via its registry but has no entry for Apple's swift-format. The existing `swiftformat` entry refers to nicklockwood/SwiftFormat — a completely different tool. Swift developers using mise cannot manage Apple's official formatter alongside their other tools, cannot declare it in `.mise.toml` for reproducible environments, and cannot benefit from mise's automatic version switching across projects.

### Current installation methods and their limitations

| Method | Prebuilt? | Version pinnable? | Requires Swift? | Cross-platform? |
|--------|-----------|-------------------|-----------------|-----------------|
| `swift format` (bundled) | ✅ | ❌ Locked to toolchain | ✅ | ⚠️ Unreliable on Linux |
| Homebrew (`brew install swift-format`) | ✅ Bottles | ⚠️ Single global version | ❌ | macOS + Linux |
| Mint | ❌ Builds from source | ✅ | ✅ | macOS + Linux |
| Manual `swift build` | ❌ | ✅ | ✅ | macOS + Linux |
| **This project (mise plugin)** | **✅** | **✅ Per-project** | **❌** | **macOS + Linux** |

The GitHub releases page for `swiftlang/swift-format` contains **zero prebuilt binaries** — only auto-generated source archives. A linked PR (#616) to add release binaries was never merged.

---

## Goals

1. **Zero-dependency installation**: `mise use apple-swift-format@602.0.0` downloads a prebuilt binary — no Swift toolchain required.
2. **Per-project version pinning**: Teams declare swift-format versions in `.mise.toml` and get automatic switching across projects.
3. **Fast Linux CI**: Statically linked Linux binaries eliminate the need for Swift Docker images in formatting-only CI steps.
4. **Upstream version tracking**: New swift-format releases are built and published within 24 hours automatically.
5. **Community contribution**: Register the tool in the mise registry so the entire Swift ecosystem benefits.

---

## How mise's tool system works and where swift-format fits

Mise's architecture centers on **backends** (installation adapters) and a **registry** (a compile-time TOML catalog mapping short names to backend specifications). The registry lives in `registry/*.toml` files in the mise repository and is baked into the binary at build time, meaning zero runtime overhead.

Each registry entry follows this format:

```toml
[tools.apple-swift-format]
description = "Apple's official formatting technology for Swift source code"
backends = ["github:your-org/swift-format-prebuilt", "spm:swiftlang/swift-format"]
test = ["swift-format --version", "{{version}}"]
os = ["macos", "linux"]
```

The `backends` array defines priority order. Mise resolves tools through this chain: explicit backend → environment variable override → registry lookup → fallback.

**Backend selection matters critically for this project.** Mise's documentation explicitly ranks backend preference:

1. **aqua** — Preferred. Uses YAML definitions from the aqua-registry, compiled into mise. Supports checksums, Cosign, SLSA provenance, and GitHub artifact attestations natively. However, swift-format would need to be added to the aqua-registry first, AND it requires prebuilt binaries to exist at a download URL.
2. **github** — Second choice. Downloads release assets directly from GitHub repos. Auto-detects the correct binary for OS/arch via a scoring algorithm. Supports `asset_pattern`, `version_prefix`, `rename_exe`, and checksum verification. This is the most practical starting point.
3. **spm** — Fallback. Clones the repo and runs `swift build -c release`. Requires Swift to be installed. Slow but works without prebuilt binaries.

The recommended architecture is: **create a new GitHub repository** (e.g., `brightdigit/swift-format-prebuilt`) that builds and publishes binaries, then register it in mise using the `github` backend as primary with `spm:swiftlang/swift-format` as fallback. This mirrors how `jdx/ruby` hosts precompiled Ruby binaries separately from the upstream Ruby repository.

---

## swift-format versioning, platform matrix, and build requirements

### Version scheme

swift-format uses a **Swift-version-encoded numbering system** since Swift 5.8. The version number encodes the target Swift release: `508.0.0` = Swift 5.8, `510.1.0` = Swift 5.10, `600.0.0` = Swift 6.0, `601.0.0` = Swift 6.1, and the latest stable is **`602.0.0`** (Swift 6.2). Pre-release tags use date suffixes like `603.0.0-prerelease-2025-12-17`. The repo has 46 total releases across its history.

A critical detail: from Swift 5.8 onward, swift-format uses the pure-Swift SwiftSyntax parser, meaning it is **decoupled from the Swift toolchain version** it targets. Any Swift compiler that can compile the code can build it.

### Platform support matrix

| Platform | Architecture | Status | Build method | Notes |
|----------|-------------|--------|-------------|-------|
| macOS | arm64 (Apple Silicon) | ✅ Full | SPM (`swift build`) | Minimum macOS 13.0 |
| macOS | x86_64 (Intel) | ✅ Full | SPM (`swift build`) | Homebrew bottles available |
| Linux | x86_64 | ✅ Full | SPM (`swift build`) | Homebrew bottles available |
| Linux | aarch64 | ✅ Full | SPM (`swift build`) | Homebrew bottles available |
| Windows | x86_64 | ⚠️ Partial | CMake (not SPM) | Deferred — see Scope |

### Build command and output

The build is straightforward: `swift build -c release` produces a **single binary** at `.build/release/swift-format`. Dependencies are swift-syntax (matching version), swift-argument-parser (≥1.2.2), and swift-markdown (≥0.2.0). No system dependencies beyond Swift itself are required. The `Package.swift` specifies `swift-tools-version: 6.0`.

---

## CI/CD pipeline design for multi-platform builds

The build pipeline should produce **4 artifacts** per release: macOS universal binary, Linux x86_64, Linux aarch64, plus SHA256 checksums for each.

### GitHub Actions runner strategy

| Target | Recommended runner | Approach |
|--------|-------------------|----------|
| macOS universal (arm64 + x86_64) | `macos-14` (Apple Silicon) | `xcrun swift build -c release --arch arm64 --arch x86_64` |
| Linux x86_64 | `macos-14` or `ubuntu-latest` | Cross-compile with Swift Static Linux SDK (`x86_64-swift-linux-musl`) or Docker `swift:6.x-jammy` |
| Linux aarch64 | `macos-14` | Cross-compile with Swift Static Linux SDK (`aarch64-swift-linux-musl`) |

The **macOS universal binary** approach: running `xcrun swift build -c release --arch arm64 --arch x86_64` on a single Apple Silicon runner creates a fat binary via `lipo`. No separate Intel runner needed.

For **Linux**, the Swift Static Linux SDK enables cross-compilation directly from a macOS arm64 runner: `swift build -c release --swift-sdk aarch64-swift-linux-musl`. This produces a fully statically linked binary with musl (no glibc dependency) that runs on any Linux distribution. A single macOS runner can produce all Linux binaries through cross-compilation.

### Static linking considerations

**Linux**: The Swift Static Linux SDK (musl-based) is the gold standard. It produces fully statically linked binaries with zero external dependencies — not even libc. These run on any Linux distribution. The limitation is no `dlopen()` support, which swift-format does not need.

**macOS**: Cannot produce fully static binaries (Darwin requires `libsystem.dylib`), but this isn't a practical concern. For distribution, code signing with a Developer ID certificate and notarization via `notarytool` are recommended but not strictly required for CLI tools.

### Asset naming convention

```
swift-format-{version}-{os}-{arch}.tar.gz
```

Examples:

- `swift-format-602.0.0-macos-universal.tar.gz`
- `swift-format-602.0.0-linux-x86_64.tar.gz`
- `swift-format-602.0.0-linux-aarch64.tar.gz`
- `swift-format-602.0.0-checksums.txt`

---

## Version synchronization strategy

The binary-hosting repo must mirror upstream swift-format tags exactly. A **scheduled GitHub Actions workflow** (e.g., daily cron) should poll `swiftlang/swift-format` releases via the GitHub API, detect new tags, and trigger builds automatically. Only stable releases (not pre-release tags containing "prerelease") should be built by default, with an option for manual dispatch on pre-releases.

The version string passed to mise should be bare (e.g., `602.0.0` — swift-format doesn't use a `v` prefix). The `test` command `swift-format --version` outputs the version string, which mise uses for verification.

### Minimum version scope

The project should initially build binaries for versions **508.0.0 and later** (Swift 5.8+), which is when swift-format decoupled from the Swift toolchain. Earlier versions require exact toolchain matching and are not practical to distribute as standalone binaries.

---

## SwiftLint as the reference implementation

SwiftLint (`realm/SwiftLint`) is already in the mise registry via both aqua and github backends and publishes comprehensive release artifacts. Its release assets include: `portable_swiftlint.zip` (macOS universal), `swiftlint_linux_amd64.zip` and `swiftlint_linux_arm64.zip` (each containing both dynamically and statically linked variants), and an SPM artifact bundle.

The naming convention follows a consistent `{tool}_{os}_{arch}.{format}` pattern that maps cleanly to both the mise github backend's asset auto-detection and aqua-registry template variables.

---

## Mise registry entry

```toml
[tools.apple-swift-format]
description = "Apple's official formatting technology for Swift source code"
backends = ["github:brightdigit/swift-format-prebuilt", "spm:swiftlang/swift-format"]
test = ["swift-format --version", "{{version}}"]
os = ["macos", "linux"]
```

The name `apple-swift-format` distinguishes it from the existing `swiftformat` (nicklockwood/SwiftFormat). The `github` backend is primary for fast prebuilt binary downloads; the `spm` backend is a fallback that builds from source when a prebuilt binary isn't available.

---

## Scope boundaries

### In scope (Phase 1)

- GitHub repository with CI pipeline for building and publishing binaries
- macOS universal, Linux x86_64, Linux aarch64 targets
- SHA256 checksums for all artifacts
- Automated upstream release tracking
- Mise registry PR (`github` backend primary, `spm` fallback)
- Versions 508.0.0+ (Swift 5.8+)

### In scope (Phase 2)

- **Platform-aware backend selection**: Investigate configuring mise to prefer the Xcode-bundled `swift format` on macOS (zero download) while using the prebuilt binary on Linux. This could involve OS-specific backend ordering or a wrapper that delegates to the toolchain version when available.
- Aqua registry entry (once binary distribution is stable)
- SPM artifact bundle as a bonus artifact
- macOS code signing and notarization
- GitHub artifact attestations (SLSA provenance)

### Out of scope

- **Windows support**: swift-format's Windows build uses CMake rather than SPM, requires dynamic SwiftSyntax linking, and runs inside Docker containers even in Apple's own CI. The added complexity versus the small user base makes it a poor initial investment.
- **Pre-5.8 versions**: These require exact Swift toolchain matching and are impractical for standalone binary distribution.

---

## Success criteria

1. `mise use apple-swift-format@602.0.0` installs a working binary within seconds on macOS (arm64 or x86_64) and Linux (x86_64 or aarch64), with no Swift toolchain required.
2. The binary-hosting repo tracks upstream releases within 24 hours.
3. All binaries include verified SHA256 checksums.
4. Linux binaries are fully statically linked (musl) with zero external dependencies.
5. The mise registry PR is accepted and the tool is available to all mise users.
6. A GitHub Actions CI step using the mise-installed swift-format completes in under 30 seconds (excluding download time).

---

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Swift Static Linux SDK incompatible with swift-syntax/swift-markdown | Low | High | Fall back to Docker-based glibc builds with `--static-swift-stdlib` |
| Upstream versioning scheme changes | Low | Medium | Monitor swift-format releases; adapt version parsing |
| macOS runners expensive for daily cron builds | Medium | Low | Only trigger builds when new upstream tags detected; cache aggressively |
| Mise registry maintainers reject naming or approach | Low | Medium | Pre-discuss in mise GitHub Discussions before opening PR |
| swift-format eventually ships prebuilt binaries upstream | Low | Positive | Would reduce maintenance burden; could redirect mise entry to upstream |
